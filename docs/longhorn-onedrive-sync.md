# Nightly Sync of Longhorn Backups to OneDrive using rclone

This document outlines a Kubernetes-native setup that automatically synchronizes Longhorn backups (stored in Backblaze B2/S3) to Microsoft OneDrive every night using an `rclone` `CronJob`.

---

## Architecture Overview

1. **Primary Backup Target**: Longhorn is configured (via `infrastructure/kubernetes/longhorn.tf`) to write volume backups to a Backblaze B2 bucket using its S3-compatible API. These backups are staggered across weekdays at `02:00`.
2. **Offsite Redundancy**: To provide additional resiliency, a nightly Kubernetes `CronJob` runs at `03:00` (shortly after the Longhorn backup processes finish).
3. **Synchronization Tool**: The CronJob runs `rclone`, a highly efficient command-line utility for syncing files. It pulls newly completed backup blocks from the Backblaze B2 remote and pushes them to Microsoft OneDrive.
4. **Configuration Storage**: All access credentials and OAuth tokens are stored securely in a Kubernetes `Secret` containing the `rclone.conf` file, keeping them out of Git and Terraform state.

---

## Step 1: Generate OneDrive OAuth Credentials (Out-of-Band)

Because Microsoft OneDrive uses OAuth2 authentication, you must perform the initial authorization step on a machine with a web browser (e.g., your local workstation), as headless servers cannot complete the interactive login.

1. Install `rclone` on your local workstation.
2. Run the interactive config generator:
   ```bash
   rclone config
   ```
3. Create a new remote named `onedrive` of type `onedrive`.
4. Follow the interactive prompts. When asked `Use auto config?`, select `Y` (Yes).
5. A browser window will open. Log in to your Microsoft/OneDrive account and grant permissions to rclone.
6. Once completed, your terminal will display the configuration block, including an OAuth `token`.
7. Retrieve the generated token string from your local `rclone.conf` (usually located at `~/.config/rclone/rclone.conf` on Linux/macOS or `%APPDATA%/rclone/rclone.conf` on Windows).

---

## Step 2: Create the Kubernetes Secret

Create a file named `rclone-secret.yaml` containing your `rclone.conf` configuration. This file contains sensitive access keys and tokens, so **do not commit this file to Git**.

> **Note**: For the Backblaze B2 endpoint, match the credentials and endpoints used in your `longhorn-backup-b2` secret.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rclone-sync-config
  namespace: longhorn-system
type: Opaque
stringData:
  rclone.conf: |
    [b2]
    type = s3
    provider = Other
    env_auth = false
    access_key_id = <YOUR_B2_KEY_ID>
    secret_access_key = <YOUR_B2_APPLICATION_KEY>
    endpoint = https://s3.eu-central-003.backblazeb2.com

    [onedrive]
    type = onedrive
    drive_id = <YOUR_ONEDRIVE_DRIVE_ID>
    drive_type = personal
    token = {"access_token":"xxxx","token_type":"Bearer","refresh_token":"xxxx","expiry":"202x-xx-xxTxx:xx:xx.xxxxxxZ"}
```

Apply the secret to your cluster:
```bash
kubectl apply -f rclone-secret.yaml
```

---

## Step 3: Define the CronJob Manifest

Below is the Kubernetes manifest for the `rclone-onedrive-sync` CronJob.

### Key Features of this Setup:
- **ARM64 Support**: Uses the official `rclone/rclone:latest` image, which natively supports both `amd64` and `arm64` architectures.
- **Timing**: Scheduled at `03:00` daily (`0 3 * * *`), allowing one hour for the staggered `02:00` Longhorn backups to complete.
- **Security Context**: Runs as a non-root user (`runAsUser: 1000`) with elevated privileges disabled and a read-only root filesystem.
- **Resource Limits**: Configures CPU and memory limits/requests to ensure the job doesn't impact other workloads on single-node or lightweight environments.
- **Robust rclone Parameters**: Uses `--checksum` to verify file integrity and restricts bandwidth/transfers to prevent throttling.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: rclone-onedrive-sync
  namespace: longhorn-system
  labels:
    app: rclone-onedrive-sync
spec:
  # Run every night at 03:00 AM
  schedule: "0 3 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  jobTemplate:
    spec:
      backoffLimit: 3
      template:
        metadata:
          labels:
            app: rclone-onedrive-sync
        spec:
          restartPolicy: OnFailure

          # Security context to ensure running as non-root
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000

          containers:
            - name: rclone
              # Multi-arch image supporting linux/arm64
              image: rclone/rclone:1.65.2
              imagePullPolicy: IfNotPresent

              # Read-only filesystem and non-escalation security practices
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop:
                    - ALL

              command: ["rclone"]
              args:
                - "sync"
                - "b2:<your-longhorn-backup-bucket-name>"
                - "onedrive:/Backups/Longhorn"
                - "--config"
                - "/etc/rclone/rclone.conf"
                - "--checksum"
                - "--transfers=4"
                - "--checkers=8"
                - "--contimeout=60s"
                - "--timeout=300s"
                - "--stats=1m"
                - "--verbose"

              # Protect the cluster by capping resource usage
              resources:
                requests:
                  cpu: "100m"
                  memory: "128Mi"
                limits:
                  cpu: "1000m"
                  memory: "512Mi"

              volumeMounts:
                - name: config-volume
                  mountPath: /etc/rclone
                  readOnly: true
                # Mount temporary memory-backed emptyDir for rclone cache/temp files
                - name: tmp-volume
                  mountPath: /tmp

          volumes:
            - name: config-volume
              secret:
                secretName: rclone-sync-config
                items:
                  - key: rclone.conf
                    path: rclone.conf
            - name: tmp-volume
              emptyDir:
                medium: Memory
```

Save this manifest (e.g., as `rclone-cronjob.yaml`) and apply it to the cluster:
```bash
kubectl apply -f rclone-cronjob.yaml
```

---

## Step 4: Verification & Operations

### 1. Manual Testing
You do not have to wait until 03:00 to test the job. You can trigger a manual job execution directly from the CronJob template:

```bash
kubectl create job --from=cronjob/rclone-onedrive-sync rclone-onedrive-sync-manual -n longhorn-system
```

### 2. Monitor execution
Watch the sync execution by following the container logs:

```bash
kubectl get pods -n longhorn-system -l app=rclone-onedrive-sync --watch
# Once the pod is running/completed:
kubectl logs -n longhorn-system -l app=rclone-onedrive-sync --tail=100
```

### 3. Check OneDrive
Verify that a `/Backups/Longhorn/` folder has been created in your OneDrive and contains the sync'd Longhorn backup blocks.
