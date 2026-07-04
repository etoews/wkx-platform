# Shared Edge network with `<service>-<env>` aliases

Status: accepted

Caddy reaches app containers over one shared Docker network, `wkx-edge`, created and named by the Platform stack. Every deployed Service joins it as an external network and registers the Edge alias `<service>-<env>` (for example `hello-prod`), which is exactly what its Caddy snippet proxies to. One network, one owner, and a stable per-env upstream name that is independent of Compose's container naming.

The alternatives: per-app networks would force Caddy to join every project's network, meaning a platform-stack change per project added and reload churn; raw container names (`hello-prod-web-1`) are Compose implementation details that shift with scaling and project naming; host networking gives up container isolation entirely. The alias contract appears in every project's `compose.yml` and snippet from M6 on, which is what makes it hard to reverse.

_Source: M3 design spec (2026-07-05) §2, §4.3, §5._
