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
              # openclaw image runs as node (uid 1000); fsGroup ensures
              # the PVC is group-writable on mount.
              securityContext = {
                runAsUser = 1000;
                runAsGroup = 1000;
                fsGroup = 1000;
              };

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
                  env = [
                    # Disable mDNS — does not work reliably in Kubernetes bridge networking.
                    { name = "OPENCLAW_DISABLE_BONJOUR"; value = "1"; }

                    # Gateway auth token — generate with: openssl rand -hex 32
                    {
                      name = "OPENCLAW_GATEWAY_TOKEN";
                      valueFrom.secretKeyRef = {
                        name = "openclaw-secrets";
                        key = "OPENCLAW_GATEWAY_TOKEN";
                      };
                    }

                    # --- LLM backend: choose one option ---

                    # Option A: Ollama (local, free — default)
                    { name = "OLLAMA_BASE_URL"; value = "http://ollama.ollama.svc.cluster.local:11434"; }

                    # Option B: Gemini Flash (comment out Option A, uncomment below)
                    # {
                    #   name = "GEMINI_API_KEY";
                    #   valueFrom.secretKeyRef = { name = "openclaw-secrets"; key = "GEMINI_API_KEY"; };
                    # }

                    # Option C: Groq (comment out Options A & B, uncomment below)
                    # {
                    #   name = "GROQ_API_KEY";
                    #   valueFrom.secretKeyRef = { name = "openclaw-secrets"; key = "GROQ_API_KEY"; };
                    # }

                    # --- Messaging channels ---

                    # Telegram
                    # {
                    #   name = "TELEGRAM_BOT_TOKEN";
                    #   valueFrom.secretKeyRef = { name = "openclaw-secrets"; key = "TELEGRAM_BOT_TOKEN"; };
                    # }

                    # Discord
                    # {
                    #   name = "DISCORD_BOT_TOKEN";
                    #   valueFrom.secretKeyRef = { name = "openclaw-secrets"; key = "DISCORD_BOT_TOKEN"; };
                    # }
                  ];
                  volumeMounts = [
                    { name = "home"; mountPath = "/home/node/.openclaw"; }
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
                { name = "home"; persistentVolumeClaim.claimName = "openclaw-home"; }
                { name = "workspace-seed"; configMap.name = "openclaw-workspace-seed"; }
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
