# Environment is always explicit, never defaulted

Status: accepted

Every namespace carries an `env` slot, and it must always be named explicitly. Per-project Terraform modules require an `env` input with no default. The deploy script requires `--env` with no default and errors out with the valid env patterns if it is missing. CI workflows hardcode their target: `pr-<number>` for PR-open jobs, `prod` for main-merge jobs. Account-level and host-level resources have no env dimension and must not gain one.

Defaulting to a "common" env hides intent and makes accidental prod deploys easy. The trade-off is slightly more verbosity on every deploy and module call, which is the point rather than a cost.

_Source: design spec §6; CLAUDE.md Invariant 1._
