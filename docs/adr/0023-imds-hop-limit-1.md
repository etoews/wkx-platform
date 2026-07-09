# IMDS hop limit 1: containers cannot reach instance credentials

Status: accepted

M5 changed the Host's `http_put_response_hop_limit` from 2 to 1 (IMDSv2 `http_tokens = "required"` unchanged), reversing M2's "hop limit 2 so containers can reach instance credentials if ever needed". With Parameters holding every Service's secrets, the instance role's credentials unlock all of `/wkx/*`; hop limit 1 stops the IMDSv2 token PUT response at the bridge-network boundary, so a compromised container cannot mint a token and assume the role.

Nothing containerised uses AWS APIs: the CloudWatch agent is host tooling (ADR 0021), the awslogs driver runs inside dockerd in the host network namespace (ADR 0020), and Env-file renders plus ECR login use the host's aws-cli. The accepted forward cost: a future containerised AWS consumer (the M10 backup runner is the candidate) must use host networking, its own credentials, or run as a host-level job.

_Source: M5 design spec (2026-07-10) §2, §4. Supersedes the hop-limit note in the M2 design spec (2026-07-04)._
