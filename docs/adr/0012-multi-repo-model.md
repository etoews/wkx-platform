# Multi-repo: a platform repo plus one repo per project

Status: accepted

The platform repo (`wkx-platform`) owns infrastructure, host bootstrap, platform services, deploy tooling, and the reference project. Each app lives in its own `wkx-<name>` project repo. A monorepo was considered and rejected: per-project repos let each app own its own issues, history, and visibility, which suits independent personal projects. The trade-off is that cross-cutting changes span repos, handled by AI fanning out PRs rather than a single edit (see ADR-0013).

_Source: design spec §8.1, §5._
