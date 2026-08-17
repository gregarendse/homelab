{ kubenix, ... }:
let
  # --- Tunables --------------------------------------------------------------
  # `sync-due` bank-syncs the least-recently-synced accounts first and skips any
  # account synced within the last `minAgeHours` (using each account's own
  # `last_sync` timestamp). That keeps every account under GoCardless' per-account
  # daily rate limit no matter how often this CronJob fires or how many accounts
  # exist — the account set is resolved on every run, so it adapts automatically.
  #
  #   limit         : max accounts to sync per run (caps work / spreads load)
  #   minAgeHours   : skip accounts synced within this many hours
  #   intervalHours : hours between runs (must divide 24 for evenly-spaced runs)
  #
  # With minAgeHours = 20 on a 6h schedule, each account is synced ~once/day —
  # comfortably under the ~4/day limit. Raise minAgeHours to sync less often, or
  # raise limit if you have many accounts that fall due in the same run.
  limit = 4;
  minAgeHours = 20;
  intervalHours = 6;

  # Fire at minute 0 every `intervalHours` hours (00:00, 06:00, ... for 6).
  schedule = "0 */${toString intervalHours} * * *";
in
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {
      namespaces."actual-sync" = { };

      # Periodically run `actual-ctl sync-due` to bank-sync any accounts that are
      # overdue. Modelled on the upstream example CronJob:
      # https://github.com/gregarendse/actual-ctl/blob/master/manifests/cronjob.example.yaml
      cronJobs."actual-sync" = {
        metadata = {
          name = "actual-sync";
          namespace = "actual-sync";
          labels."app.kubernetes.io/name" = "actual-ctl";
        };
        spec = {
          schedule = schedule;
          timeZone = "Etc/UTC";
          # Never let a slow run overlap the next scheduled one.
          concurrencyPolicy = "Forbid";
          startingDeadlineSeconds = 300;
          successfulJobsHistoryLimit = 3;
          failedJobsHistoryLimit = 3;
          jobTemplate.spec = {
            # `--min-age` makes a retry safe (accounts synced on the failed
            # attempt are skipped), so allow a single retry but no hammering.
            backoffLimit = 1;
            activeDeadlineSeconds = 900;
            # Clean finished Jobs up after two days.
            ttlSecondsAfterFinished = 172800;
            template = {
              metadata.labels."app.kubernetes.io/name" = "actual-ctl";
              spec = {
                restartPolicy = "Never";
                automountServiceAccountToken = false;

                containers = [
                  {
                    name = "actual-ctl";
                    # Pin to a digest or release tag for production instead of
                    # :latest if you want reproducible rollouts.
                    image = "ghcr.io/gregarendse/actual-ctl:latest";
                    imagePullPolicy = "Always";

                    # The distroless image's entrypoint is `node` and its default
                    # CMD is `dist/index.js`; override CMD to append the
                    # subcommand and flags. (The upstream example omits
                    # `dist/index.js`; it is required here because the entrypoint
                    # is bare `node`.)
                    args = [
                      "dist/index.js"
                      "sync-due"
                      "--limit"
                      (toString limit)
                      "--min-age"
                      (toString minAgeHours)
                    ];

                    env = [
                      {
                        name = "DATA_DIR";
                        value = "/data";
                      }
                    ];

                    # SERVER_URL, SYNC_ID and PASSWORD come from the Secret (see
                    # README). Create it in this namespace before first deploy.
                    envFrom = [
                      { secretRef.name = "actual-ctl"; }
                    ];

                    volumeMounts = [
                      {
                        name = "data";
                        mountPath = "/data";
                      }
                    ];

                    resources = {
                      requests = {
                        cpu = "50m";
                        memory = "128Mi";
                      };
                      limits = {
                        memory = "512Mi";
                      };
                    };
                  }
                ];

                volumes = [
                  {
                    # Ephemeral budget cache; re-downloaded on every run. Swap for
                    # a PVC if you'd rather persist it between runs.
                    name = "data";
                    emptyDir = { };
                  }
                ];
              };
            };
          };
        };
      };
    };
  };
}
