# Terraform for all infrastructure as code

Status: accepted

One tool, Terraform, manages all infrastructure: AWS resources, Cloudflare zones and records, and Docker on the home server. This replaces the original brief's CDK-and-bash split. A single tool spanning all three targets keeps one mental model and one state discipline. Recorded explicitly so the CDK split is not reintroduced by habit.

_Source: design spec §8.1._
