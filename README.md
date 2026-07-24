# Canonry Status

Public, static service-status snapshots for Canonry.

The Mac-based watchdog writes `docs/status.json` after its independent checks.
GitHub Pages serves the static site, so the status page does not depend on the
production box being online. The snapshot intentionally excludes tailnet-only
operator services, host metrics, addresses, and alerting details.
