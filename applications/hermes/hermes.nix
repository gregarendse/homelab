# Hermes Agent — kubenix deployment
#
# Provider is controlled by which config YAML file is inlined into the
# hermes-config ConfigMap.  Switch by changing the builtins.readFile path:
#
#   Variant A (default) — Local Ollama:  ./config-ollama.yaml
#   Variant B           — Cloud:         ./config-cloud.yaml
#
# Secrets (API keys, bot tokens) are mounted from the hermes-secrets Secret
# as environment variables via envFrom.  See hermes-secrets.example.yaml.

{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {

      # ── Namespace ──────────────────────────────────────────────────────────
      namespaces.hermes = {};

      # ── Persistent storage for /opt/data ───────────────────────────────────
      # Holds sessions/, memories/, skills/, SOUL.md, logs/, cron/, hooks/.
      # Grows with usage; 5 Gi is comfortable for a personal instance.
      persistentVolumeClaims."hermes-data" = {
        metadata = {
          name = "hermes-data";
          namespace = "hermes";
          labels.app = "hermes";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "5Gi";
          storageClassName = "longhorn";
        };
      };

      # ── Provider configuration ─────────────────────────────────────────────
      # The config YAML is inlined at evaluation time via builtins.readFile so
      # the Nix expression stays clean and the config is plain YAML.
      # It is mounted over the PVC at /opt/data/config.yaml (subPath) so that
      # provider settings are GitOps-managed and cannot drift at runtime.
      #
      # To switch provider, change the path below and update hermes-secrets
      # to include the matching API key.
      configMaps."hermes-config" = {
        metadata = {
          name = "hermes-config";
          namespace = "hermes";
          labels.app = "hermes";
        };
#        data."config.yaml" = builtins.readFile ./config-ollama.yaml;
        # Variant B — cloud provider:
         data."config.yaml" = builtins.readFile ./config-cloud.yaml;
      };

      # ── Deployment ─────────────────────────────────────────────────────────
      deployments.hermes = {
        metadata = {
          name = "hermes";
          namespace = "hermes";
          labels.app = "hermes";
        };
        spec = {
          replicas = 1;
          # Recreate avoids two pods writing to the same /opt/data PVC.
          # The Hermes docs explicitly warn against concurrent gateway access
          # to the same data directory.
          strategy.type = "Recreate";
          selector.matchLabels.app = "hermes";
          template = {
            metadata.labels.app = "hermes";
            spec = {
              automountServiceAccountToken = false;
              # fsGroup must match the hermes user UID (10000) inside the
              # official image so the PVC is writable after the entrypoint
              # drops privileges via gosu.
              securityContext.fsGroup = 10000;

              # NOTE: Do NOT set runAsNonRoot or runAsUser here.
              # The official entrypoint starts as root and gosu-drops to UID
              # 10000 (hermes).  Forcing non-root at the pod level prevents
              # the entrypoint from bootstrapping /opt/data correctly.

              containers = [
                {
                  name = "hermes";
                  image = "nousresearch/hermes-agent:latest";
                  imagePullPolicy = "Always";

                  # Pass args (not command) so the official entrypoint.sh runs
                  # first: it bootstraps /opt/data and gosu-drops to the hermes
                  # user before exec-ing the gateway.
                  args = [ "gateway" "run" ];

                  ports = [
                    { name = "gateway";   containerPort = 8642; protocol = "TCP"; }
                    { name = "dashboard"; containerPort = 9119; protocol = "TCP"; }
                  ];

                  # Static, non-secret configuration committed in plain text.
                  env = [
#                  The dashboard has no auth on it, so its not safe to expose publicly. ToDo: Can we expose this safely?
#                    { name = "HERMES_DASHBOARD";      value = "1"; }
#                    { name = "HERMES_DASHBOARD_HOST"; value = "0.0.0.0"; }
#                    { name = "HERMES_DASHBOARD_PORT"; value = "9119"; }
                    { name = "HERMES_UID";            value = "10000"; }
                    { name = "HERMES_GID";            value = "10000"; }
                    { name = "API_SERVER_ENABLED";    value = "true"; }
                    { name = "API_SERVER_HOST";       value = "0.0.0.0"; }
                    { name = "HASS_URL";              value = "http://home-assistant.home-assistant:8123"; }
                  ];

                  # All secret values (API keys, bot tokens, etc.) are injected
                  # from the hermes-secrets Secret.  See hermes-secrets.example.yaml
                  # for the full list of supported keys.
                  envFrom = [
                    { secretRef.name = "hermes-secrets"; }
                  ];

                  # Gateway has a slow startup on first run (bootstraps /opt/data,
                  # syncs bundled skills).  Give it up to 5 minutes.
                  startupProbe = {
                    tcpSocket.port = "gateway";
                    periodSeconds    = 10;
                    timeoutSeconds   = 5;
                    failureThreshold = 30;
                  };
                  readinessProbe = {
                    tcpSocket.port = "gateway";
                    periodSeconds    = 15;
                    timeoutSeconds   = 5;
                    failureThreshold = 3;
                  };
                  livenessProbe = {
                    tcpSocket.port = "gateway";
                    periodSeconds    = 30;
                    timeoutSeconds   = 5;
                    failureThreshold = 3;
                  };

                  # Sized for Hermes without browser tools (Playwright/Chromium
                  # disabled).  Bump memory limit to 3–4 Gi and the /dev/shm
                  # emptyDir sizeLimit if you enable HERMES_BROWSER=1.
                  resources = {
                    requests = {
                      cpu    = "250m";
                      memory = "512Mi";
                    };
                    limits = {
                      cpu    = "1000m";
                      memory = "2048Mi";
                    };
                  };

                  volumeMounts = [
                    {
                      # Primary data volume: sessions, memories, skills, SOUL.md.
                      name      = "hermes-data";
                      mountPath = "/opt/data";
                    }
                    {
                      # GitOps-managed provider config overlaid on the PVC.
                      # subPath ensures only config.yaml is replaced; all other
                      # /opt/data paths continue to read from the PVC.
                      name      = "hermes-config";
                      mountPath = "/opt/data/config.yaml";
                      subPath   = "config.yaml";
                      readOnly  = true;
                    }
                    {
                      # Shared memory for Playwright/Chromium.  Harmless when
                      # browser tools are not in use.
                      name      = "dshm";
                      mountPath = "/dev/shm";
                    }
                    {
                      name      = "tmp-volume";
                      mountPath = "/tmp";
                    }
                  ];
                }
              ];

              volumes = [
                {
                  name = "hermes-data";
                  persistentVolumeClaim.claimName = "hermes-data";
                }
                {
                  name           = "hermes-config";
                  configMap.name = "hermes-config";
                }
                {
                  # 1 Gi shared memory for Playwright.  Safe to reduce to 256Mi
                  # if browser tools will never be enabled.
                  name     = "dshm";
                  emptyDir = {
                    medium    = "Memory";
                    sizeLimit = "1Gi";
                  };
                }
                {
                  name     = "tmp-volume";
                  emptyDir = {};
                }
              ];
            };
          };
        };
      };

      # ── Services ─────────────────────────────────────────────────────────
      services.hermes = {
        metadata = {
          name      = "hermes";
          namespace = "hermes";
          labels.app = "hermes";
        };
        spec = {
          type         = "ClusterIP";
          selector.app = "hermes";
          ports = [
            { name = "gateway";   port = 8642; targetPort = "gateway";   protocol = "TCP"; }
            { name = "dashboard"; port = 9119; targetPort = "dashboard"; protocol = "TCP"; }
          ];
        };
      };

      # ── Ingress (dashboard) ───────────────────────────────────────────────
      # Exposes the Hermes web dashboard via Traefik + Cloudflare + cert-manager.
      # Update the hostname to match your domain before enrolling in apps.yaml.
#      ingresses."hermes-ingress" = {
#        metadata = {
#          name      = "hermes-ingress";
#          namespace = "hermes";
#          annotations = {
#            "external-dns.alpha.kubernetes.io/cloudflare-proxied" = "true";
#            "external-dns.alpha.kubernetes.io/cloudflare-tags"    = "app=hermes,env=prod,owner=homelab";
#            "cert-manager.io/cluster-issuer"                      = "letsencrypt-prod";
#            "traefik.ingress.kubernetes.io/router.entrypoints"    = "websecure";
#            "traefik.ingress.kubernetes.io/router.tls"            = "true";
#          };
#        };
#        spec = {
#          ingressClassName = "traefik";
#          tls = [
#            {
#              hosts      = [ "hermes.arendse.nom.za" ];
#              secretName = "hermes-tls";
#            }
#          ];
#          rules = [
#            {
#              host = "hermes.arendse.nom.za";
#              http.paths = [
#                {
#                  path     = "/";
#                  pathType = "Prefix";
#                  backend.service = {
#                    name = "hermes";
#                    # Route to the dashboard port (9119), not the gateway API.
#                    port.number = 9119;
#                  };
#                }
#              ];
#            }
#          ];
#        };
#      };

    };
  };
}
