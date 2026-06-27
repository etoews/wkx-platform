# No SSH; access via SSM Session Manager only

Status: accepted

Port 22 stays closed on the host. There is no key pair, no bastion, and no security group rule for SSH. All shell access goes through AWS SSM Session Manager, which is IAM-gated, audit-logged, and needs no keys to rotate. The trade-off is that access depends on the SSM agent and the instance role staying healthy; recovery from a broken agent is via instance replacement, which the single-instance design already tolerates.

_Source: design spec §8.2; CLAUDE.md Invariant 2._
