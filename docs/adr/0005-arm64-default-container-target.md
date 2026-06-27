# ARM64 is the default container target

Status: accepted

Containers build for `linux/arm64` by default to match the Graviton host, which is significantly cheaper than x86. `amd64` is opt-in per project via a multi-arch build, for images that also need to run on the x86 home server. The trade-off is that a project destined for the home server must remember to enable the multi-arch build; the default favours the cloud target, which is the priority.

_Source: design spec §8.1; CLAUDE.md Invariant 4._
