# The CloudWatch agent is Layer 2 host tooling, not a platform service

Status: accepted

The CloudWatch agent runs as a GPG-verified host deb installed by cloud-init and configured from SSM Parameter Store (`/wkx/platform/<env>/CLOUDWATCH_AGENT_CONFIG`), handling only host-level concerns: syslog into `/wkx/platform/<env>` and CPU, memory, disk, and network metrics. The original design spec placed it in Layer 3 as a platform service in `platform/compose.yml`; M4 corrected the spec and glossary instead of containerising the agent.

A containerised agent would need `/proc`, `/var/log`, and Docker log-directory host mounts plus elevated privileges, and it observes the box it runs on, so it gains nothing from living inside the Compose stack it is meant to watch. Container log shipping went to the Docker daemon (ADR 0020), leaving the agent nothing container-shaped to do.

_Source: M4 design spec (2026-07-06) §1, §4._
