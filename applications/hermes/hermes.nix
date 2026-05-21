# Hermes Agent — kubenix deployment
#
# Two provider configurations are available via the hermes-config ConfigMap:
#
#   VARIANT A (default): Local Ollama
#     → points at http://ollama.ollama.svc.cluster.local:11434/v1
#     → no cloud API key required
#
#   VARIANT B: Cloud provider (OpenAI or Gemini)
#     → swap the config.yaml block in configMaps."hermes-config" below
#     → uncomment the API key env vars in the Deployment
#     → create hermes-secrets with the appropriate key (see README)
#
# ⚠️  ARM64 CHECK REQUIRED before deploying:
#     docker manifest inspect nousresearch/hermes-agent:latest | grep architecture
#     The OCI nodes are aarch64. If linux/arm64 is absent, the pod will
#     CrashLoop.  See README for mitigation options.

{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {

      # ── Namespace ──────────────────────────────────────────────────────────
      namespaces.hermes = {};

      # ── Persistent storage for /opt/data ───────────────────────────────────
      # Holds sessions/, memories/, skills/, .env, SOUL.md, logs/, etc.
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
      # The ConfigMap is mounted over the PVC at /opt/data/config.yaml so that
      # provider settings are GitOps-managed and not drifted at runtime.
      #
      # Hermes reads config.yaml on startup; the entrypoint will NOT overwrite
      # it because it only copies defaults when the file is absent.
      configMaps."hermes-config" = {
        metadata = {
          name = "hermes-config";
          namespace = "hermes";
          labels.app = "hermes";
        };
        data = {
          # ── VARIANT A: Local Ollama (default) ──────────────────────────────
          # Adjust `model` to match whatever is pulled in your Ollama instance,
          # e.g. llama3.2:3b, mistral:7b, qwen2.5:7b, etc.
          "config.yaml" = ''
            model:
              provider: custom
              model: llama3.2:3b
              base_url: http://ollama.ollama.svc.cluster.local:11434/v1
              api_key: "none"
            gateway:
              enabled: true
            api_server:
              enabled: true
              host: "0.0.0.0"
              port: 8642
          '';

          # ── VARIANT B: Cloud provider ──────────────────────────────────────
          # To switch, replace the "config.yaml" block above with one of these
          # and uncomment the matching env var in the Deployment below.
          #
          # OpenAI:
          # "config.yaml" = ''
          #   model:
          #     provider: openai
          #     model: gpt-4o
          #   gateway:
          #     enabled: true
          #   api_server:
          #     enabled: true
          #     host: "0.0.0.0"
          #     port: 8642
          # '';
          #
          # Gemini:
          # "config.yaml" = ''
          #   model:
          #     provider: google
          #     model: gemini-2.0-flash
          #   gateway:
          #     enabled: true
          #   api_server:
          #     enabled: true
          #     host: "0.0.0.0"
          #     port: 8642
          # '';
        };
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

                  # ⚠️  Verify ARM64 support before deploying:
                  #   docker manifest inspect nousresearch/hermes-agent:latest
                  # If linux/arm64 is absent the pod will CrashLoop on these
                  # aarch64 nodes.  See README for workarounds.
                  image = "nousresearch/hermes-agent:latest";
                  imagePullPolicy = "IfNotPresent";

                  # Pass args (not command) so the official entrypoint.sh
                  # runs first; it bootstraps /opt/data and drops to hermes
                  # user before exec-ing this command.
                  args = [ "gateway" "run" ];

                  ports = [
                    {
                      name = "gateway";
                      containerPort = 8642;
                      protocol = "TCP";
                    }
                    {
                      name = "dashboard";
                      containerPort = 9119;
                      protocol = "TCP";
                    }
                  ];

                  env = [
                    # Run the web dashboard as a side-process within the container.
                    { name = "HERMES_DASHBOARD";      value = "1"; }
                    { name = "HERMES_DASHBOARD_HOST"; value = "0.0.0.0"; }
                    { name = "HERMES_DASHBOARD_PORT"; value = "9119"; }

                    # Tell the entrypoint which UID to gosu into.
                    { name = "HERMES_UID"; value = "10000"; }
                    { name = "HERMES_GID"; value = "10000"; }

                    # Expose the OpenAI-compatible API server on port 8642.
                    { name = "API_SERVER_ENABLED"; value = "true"; }
                    { name = "API_SERVER_HOST";    value = "0.0.0.0"; }

                    # Required when API_SERVER_ENABLED=true (min 8 chars).
                    # Create the secret: see README → Prerequisites → Secrets.
                    {
                      name = "API_SERVER_KEY";
                      valueFrom.secretKeyRef = {
                        name = "hermes-secrets";
                        key  = "API_SERVER_KEY";
                      };
                    }

                    # ── VARIANT B: Cloud provider keys ─────────────────────
                    # Uncomment ONE of these when using a cloud provider.
                    # Also update configMaps."hermes-config" above.
                    #
                    # OpenAI:
                    # {
                    #   name = "OPENAI_API_KEY";
                    #   valueFrom.secretKeyRef = {
                    #     name = "hermes-secrets";
                    #     key  = "OPENAI_API_KEY";
                    #   };
                    # }
                    #
                    # Gemini / Google AI:
                    # {
                    #   name = "GEMINI_API_KEY";
                    #   valueFrom.secretKeyRef = {
                    #     name = "hermes-secrets";
                    #     key  = "GEMINI_API_KEY";
                    #   };
                    # }

                    # ── Optional: messaging platform tokens ────────────────
                    # {
                    #   name = "TELEGRAM_BOT_TOKEN";
                    #   valueFrom.secretKeyRef = {
                    #     name = "hermes-secrets";
                    #     key  = "TELEGRAM_BOT_TOKEN";
                    #   };
                    # }
                    # {
                    #   name = "DISCORD_BOT_TOKEN";
                    #   valueFrom.secretKeyRef = {
                    #     name = "hermes-secrets";
                    #     key  = "DISCORD_BOT_TOKEN";
                    #   };
                    # }
                  ];

                  # Gateway has a slow startup on first run (bootstraps /opt/data,
                  # may pull model metadata, etc.). Give it 5 minutes.
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
                  # disabled).  Bump memory limit to 3-4 Gi if you enable
                  # HERMES_BROWSER=1 for web browsing tasks.
                  # OCI Always Free headroom: ~2 OCPU / 12 Gi remaining across
                  # both nodes after existing workloads.
                  resources = {
                    requests = {
                      cpu    = "250m";
                      memory = "512Mi";
                    };
                    limits = {
                      cpu    = "1000m";
                      memory = "1536Mi";
                    };
                  };

                  volumeMounts = [
                    {
                      # Primary data volume: sessions, memories, skills, .env
                      name      = "hermes-data";
                      mountPath = "/opt/data";
                    }
                    {
                      # GitOps-managed provider config overlaid on the PVC.
                      # Uses subPath so only config.yaml is replaced; the rest
                      # of /opt/data continues to use the PVC.
                      name      = "hermes-config";
                      mountPath = "/opt/data/config.yaml";
                      subPath   = "config.yaml";
                      readOnly  = true;
                    }
                    {
                      # Playwright/Chromium needs /dev/shm for shared memory.
                      # This is a no-op when browser tools are disabled but
                      # harmless to keep in place.
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
                  name      = "hermes-config";
                  configMap.name = "hermes-config";
                }
                {
                  # 1 Gi shared memory for Playwright — safe to reduce to
                  # 256Mi if you never enable browser tools.
                  name    = "dshm";
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

      # ── Services ───────────────────────────────────────────────────────────
      services.hermes = {
        metadata = {
          name      = "hermes";
          namespace = "hermes";
          labels.app = "hermes";
        };
        spec = {
          type     = "ClusterIP";
          selector.app = "hermes";
          ports = [
            {
              name       = "gateway";
              port       = 8642;
              targetPort = "gateway";
              protocol   = "TCP";
            }
            {
              name       = "dashboard";
              port       = 9119;
              targetPort = "dashboard";
              protocol   = "TCP";
            }
          ];
        };
      };

      # ── Ingress (dashboard) ────────────────────────────────────────────────
      # Exposes the Hermes web dashboard via Traefik + Cloudflare + cert-manager.
      # Update the hostname to match your domain before enrolling.
      ingresses."hermes-ingress" = {
        metadata = {
          name      = "hermes-ingress";
          namespace = "hermes";
          annotations = {
            "external-dns.alpha.kubernetes.io/cloudflare-proxied" = "true";
            "external-dns.alpha.kubernetes.io/cloudflare-tags"    = "app=hermes,env=prod,owner=homelab";
            "cert-manager.io/cluster-issuer"                      = "letsencrypt-prod";
            "traefik.ingress.kubernetes.io/router.entrypoints"    = "websecure";
            "traefik.ingress.kubernetes.io/router.tls"            = "true";
          };
        };
        spec = {
          ingressClassName = "traefik";
          tls = [
            {
              # TODO: update to your domain
              hosts      = [ "hermes.arendse.nom.za" ];
              secretName = "hermes-tls";
            }
          ];
          rules = [
            {
              host = "hermes.arendse.nom.za";
              http.paths = [
                {
                  path     = "/";
                  pathType = "Prefix";
                  backend.service = {
                    name = "hermes";
                    # Route to the dashboard port (9119), not the gateway API.
                    port.number = 9119;
                  };
                }
              ];
            }
          ];
        };
      };

    };
  };
}
