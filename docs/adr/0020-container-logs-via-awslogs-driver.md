# Container logs ship via the Docker `awslogs` driver

Status: accepted

Every Compose service's stdout and stderr goes straight to its `/wkx/<service>/<env>` log group via Docker's `awslogs` log driver, configured in a cloud-only `compose.cloud.yml` overlay beside each `compose.yml` and authenticated by the instance role. Dual logging keeps `docker logs` working on the box, and base compose files stay driver-free so the home server never sees AWS config.

The alternatives: the roadmap's original wording had the CloudWatch agent tailing Docker's JSON log files, but those live under content-addressed container paths (`/var/lib/docker/containers/<container-id>/`), so the agent's path-to-group mapping cannot route them per service without a fragile deploy-time shim; one merged log group would break the `/wkx/<service>/<env>` naming pattern; a containerised log shipper adds host mounts and privileges for no gain on a single box. The overlay pair enters the platform contract (every project from the M8 reference project on), which is what makes it hard to reverse.

_Source: M4 design spec (2026-07-06) §2, §3._
