{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {
      namespaces.openclaw = {};

      persistentVolumeClaims.openclaw-home = {
        metadata = {
          name = "openclaw-home";
          namespace = "openclaw";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "5Gi";
          storageClassName = "longhorn";
        };
      };

      configMaps.openclaw-workspace-seed = {
        metadata = {
          name = "openclaw-workspace-seed";
          namespace = "openclaw";
        };
        data = {
          "SOUL.md" = builtins.readFile ./workspace/SOUL.md;
          "homelab-SKILL.md" = builtins.readFile ./workspace/skills/homelab/SKILL.md;
          "personal-context-SKILL.md" = builtins.readFile ./workspace/skills/personal-context/SKILL.md;
          "security-SKILL.md" = builtins.readFile ./workspace/skills/security/SKILL.md;
          "terraform-nix-SKILL.md" = builtins.readFile ./workspace/skills/terraform-nix/SKILL.md;
        };
      };

      deployments.openclaw = {
        metadata = {
          name = "openclaw";
          namespace = "openclaw";
          labels = { app = "openclaw"; };
        };
        spec = {
          replicas = 1;
          # Recreate ensures the old pod fully terminates before the new one
          # starts — required for single-instance stateful apps with RWO volumes.
          strategy.type = "Recreate";
          selector.matchLabels = { app = "openclaw"; };
          template = {
            metadata.labels = { app = "openclaw"; };
            spec = {
              # Pod-level: sets ownership of PVC mounts via fsGroup.
              # runAsUser/Group are NOT set here so the init container can
              # override to root without conflict.
              securityContext.fsGroup = 1000;

              initContainers = [
                {
                  name = "init-workspace";
                  image = "busybox:stable";
                  imagePullPolicy = "IfNotPresent";
                  # Seeds workspace files from the ConfigMap on first deployment.
                  # Uses [ ! -f ] guards so user edits in the PVC are never overwritten.
                  # To reset a file to the repo default, delete it from the PVC
                  # and restart the pod.
                  command = [
                    "/bin/sh"
                    "-c"
                    ''
                      set -e
                      mkdir -p /data/workspace/skills/homelab
                      mkdir -p /data/workspace/skills/personal-context
                      mkdir -p /data/workspace/skills/security
                      mkdir -p /data/workspace/skills/terraform-nix
                      [ ! -f /data/workspace/SOUL.md ] && \
                        cp /config/SOUL.md /data/workspace/SOUL.md && \
                        echo "Seeded SOUL.md" || echo "SOUL.md exists, skipping"
                      [ ! -f /data/workspace/skills/homelab/SKILL.md ] && \
                        cp /config/homelab-SKILL.md /data/workspace/skills/homelab/SKILL.md && \
                        echo "Seeded homelab skill" || echo "homelab skill exists, skipping"
                      [ ! -f /data/workspace/skills/personal-context/SKILL.md ] && \
                        cp /config/personal-context-SKILL.md /data/workspace/skills/personal-context/SKILL.md && \
                        echo "Seeded personal-context skill" || echo "personal-context skill exists, skipping"
                      [ ! -f /data/workspace/skills/security/SKILL.md ] && \
                        cp /config/security-SKILL.md /data/workspace/skills/security/SKILL.md && \
                        echo "Seeded security skill" || echo "security skill exists, skipping"
                      [ ! -f /data/workspace/skills/terraform-nix/SKILL.md ] && \
                        cp /config/terraform-nix-SKILL.md /data/workspace/skills/terraform-nix/SKILL.md && \
                        echo "Seeded terraform-nix skill" || echo "terraform-nix skill exists, skipping"
                      chown -R 1000:1000 /data
                    ''
                  ];
                  securityContext = {
                    runAsUser = 0;
                    runAsGroup = 0;
                    allowPrivilegeEscalation = false;
                  };
                  volumeMounts = [
                    { name = "home"; mountPath = "/data"; }
                    { name = "workspace-seed"; mountPath = "/config"; readOnly = true; }
                  ];
                  resources = {
                    requests = { cpu = "10m"; memory = "32Mi"; };
                    limits = { cpu = "100m"; memory = "64Mi"; };
                  };
                }
              ];

              containers = [
                {
                  name = "openclaw";
                  image = "ghcr.io/openclaw/openclaw:latest";
                  imagePullPolicy = "IfNotPresent";
                  ports = [
                    { name = "http"; containerPort = 18789; protocol = "TCP"; }
                  ];
                  # Non-secret config — values that are safe to have in the manifest.
                  env = [
                    # Disable mDNS — does not work reliably in Kubernetes bridge networking.
                    { name = "OPENCLAW_DISABLE_BONJOUR"; value = "1"; }
                    # LLM backend base URL for Ollama (local, free — default).
                    # To switch to a cloud provider, remove this and add the
                    # relevant API key to openclaw-secrets instead
                    # (e.g. GEMINI_API_KEY, GROQ_API_KEY).
                    { name = "OLLAMA_BASE_URL"; value = "http://ollama.ollama.svc.cluster.local:11434"; }
                  ];
                  # All secrets injected from the openclaw-secrets Secret.
                  # Add or remove keys in the Secret without touching this manifest.
                  # Expected keys (all optional except OPENCLAW_GATEWAY_TOKEN):
                  #   OPENCLAW_GATEWAY_TOKEN  — required; generate: openssl rand -hex 32
                  #   GEMINI_API_KEY          — cloud LLM (Option B)
                  #   GROQ_API_KEY            — cloud LLM (Option C)
                  #   TELEGRAM_BOT_TOKEN      — messaging channel
                  #   DISCORD_BOT_TOKEN       — messaging channel
                  envFrom = [
                    { secretRef.name = "openclaw-secrets"; }
                  ];
                  securityContext = {
                    runAsNonRoot             = true;
                    runAsUser                = 1000;
                    runAsGroup               = 1000;
                    allowPrivilegeEscalation = false;
                    readOnlyRootFilesystem   = true;
                    capabilities.drop        = [ "ALL" ];
                  };
                  volumeMounts = [
                    { name = "home"; mountPath = "/home/node/.openclaw"; }
                    # readOnlyRootFilesystem requires an explicit writable /tmp.
                    # If openclaw writes to other paths at runtime (e.g. ~/.npm,
                    # ~/.config), add emptyDir mounts here and open a PR to document them.
                    { name = "tmp";  mountPath = "/tmp"; }
                  ];
                  readinessProbe = {
                    httpGet = { path = "/readyz"; port = "http"; };
                    initialDelaySeconds = 10;
                    periodSeconds = 10;
                    timeoutSeconds = 3;
                    failureThreshold = 3;
                  };
                  livenessProbe = {
                    httpGet = { path = "/healthz"; port = "http"; };
                    initialDelaySeconds = 30;
                    periodSeconds = 20;
                    timeoutSeconds = 3;
                    failureThreshold = 3;
                  };
                  resources = {
                    requests = {
                      cpu = "250m";
                      memory = "512Mi";
                    };
                    limits = {
                      cpu = "1000m";  # leave headroom for ollama on the same node
                      memory = "1Gi";
                    };
                  };
                }
              ];

              volumes = [
                { name = "home";           persistentVolumeClaim.claimName = "openclaw-home"; }
                { name = "workspace-seed"; configMap.name = "openclaw-workspace-seed"; }
                # Writable scratch space required by readOnlyRootFilesystem = true.
                { name = "tmp";            emptyDir = {}; }
              ];
            };
          };
        };
      };

      services.openclaw = {
        metadata = {
          name = "openclaw";
          namespace = "openclaw";
          labels = { app = "openclaw"; };
        };
        spec = {
          type = "ClusterIP";
          selector = { app = "openclaw"; };
          ports = [
            { name = "http"; port = 18789; targetPort = "http"; protocol = "TCP"; }
          ];
        };
      };

    };
  };
}
