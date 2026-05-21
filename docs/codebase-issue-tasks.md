# Codebase issue task proposals

This document captures four actionable tasks found during a light audit of the repository.

## 1) Typo fix task
**Task:** Fix the typo `ClusterIp` to `ClusterIP` in the connectivity test output header.

- **Where:** `scripts/connectivity_test.py` in `print_results()`.
- **Why it matters:** `ClusterIP` is the Kubernetes field name and is already used consistently elsewhere in the same script (`cluster_ip` variable), so the current label looks inconsistent to operators.
- **Acceptance criteria:** Running the script prints `ClusterIP` exactly in the header row.

## 2) Bug fix task
**Task:** Handle Kubernetes services with `spec.clusterIP: "None"` and avoid invoking `nc` with invalid addresses.

- **Where:** `scripts/connectivity_test.py` in service collection and connectivity test flow.
- **Problem detail:** The script skips `None` cluster IPs, but does not explicitly guard against other non-routable or malformed values (for example from API edge-cases or future schema changes), and silently counts failed subprocess invocations as connectivity failures.
- **Why it matters:** This can produce misleading results where infrastructure/data issues are reported as network issues.
- **Acceptance criteria:**
  - Invalid addresses are detected before launching `nc`.
  - Output distinguishes input validation errors from true connection failures.

## 3) Comment / documentation discrepancy task
**Task:** Fix stale or inaccurate README phrasing in the Go CI tool docs.

- **Where:** `src/go/ci/README.md`.
- **Problem detail:** The header says `# ci` and describes “A Golang project.”, while command descriptions elsewhere refer to `ci-tool`; testing instructions use outdated markdown formatting (``make test``) and are less clear than standard fenced code blocks.
- **Why it matters:** The README is the first onboarding artifact and should match actual binary naming and modern markdown conventions.
- **Acceptance criteria:**
  - README consistently uses one project/binary name.
  - Testing instructions are presented as executable command snippets.

## 4) Test improvement task
**Task:** Add unit tests for table formatting and truncation behavior in the connectivity script.

- **Where:** new tests for `scripts/connectivity_test.py` functions `truncate()` and `print_results()`.
- **Why it matters:** These functions are pure/predictable and easy to regress during formatting changes; currently there is no automated safety net for output shape.
- **Acceptance criteria:**
  - Tests validate truncation length boundaries and ellipsis behavior.
  - Tests validate header spellings and column widths for at least one representative row.
