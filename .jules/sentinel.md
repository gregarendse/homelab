### 2026-09-14 — Home Assistant Root Requirement & Security Context

**Finding:** `ghcr.io/home-assistant/home-assistant:stable` requires root privileges (`uid=0`) on startup due to its `s6-overlay` init system and permission setup.
**Learning:** Forcing `runAsNonRoot: true` or `runAsUser: 1000` causes Home Assistant container startup failure (`CrashLoopBackOff`). Container capability drop (`capabilities.drop = ["ALL"]`) and `allowPrivilegeEscalation = false` can be applied safely to workloads like Pi-hole with specific capability allowances (`NET_ADMIN`, `NET_BIND_SERVICE`, `NET_RAW`, `SYS_TIME`).
**Prevention:** Do not enforce `runAsNonRoot` on `home-assistant` without custom non-root container image preparation. Ensure `clusters/oci/rendered/` JSON formatting matches existing file structure during manual updates.
