# Single-instance Docker Compose architecture

Status: accepted

Everything runs on one ARM Graviton EC2 instance (t4g.medium) orchestrated by Docker Compose: no high availability, no autoscaling, and no container orchestrator (Kubernetes, ECS). Personal traffic does not warrant redundancy, and an ALB plus a second instance would consume the entire NZD $50/mo budget on its own. The trade-off is 5 to 15 minutes of downtime during instance replacement, covered by backups and a documented restore drill.

_Source: design spec §8.1; this is the keystone shape the other ADRs assume._
