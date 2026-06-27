# Public files carry placeholders, never real account state

Status: accepted

Every committed file (specs, plans, setup templates, all of them) uses placeholders such as `<PLATFORM_ACCOUNT_ID>` and `<CLOUDFLARE_ACCOUNT_ID>`. Real AWS account IDs, IAM Identity Center ARNs, and Cloudflare account and zone IDs live only in gitignored `docs/setup/*.local.md` siblings. The repo is public, so a real identifier landing in any committed file is a leak that is hard to walk back. The trade-off is that each contributor keeps a local, uncommitted file holding the real values.

_Source: CLAUDE.md Invariant 7._
