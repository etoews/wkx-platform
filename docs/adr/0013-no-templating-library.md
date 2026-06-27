# No templating library; copy the reference project and fan out with AI

Status: accepted

New projects are created by copying the reference project (`template/`) and substituting name, port, and hostname, not with cookiecutter, copier, or a similar tool. For ten or fewer personal projects with AI-assisted development, a generic templating tool is more weight than it earns. The reference project is itself a real, CI-tested working app, so it cannot rot the way an abstract template can. Cross-cutting changes ("add a HEALTHCHECK to every Dockerfile") are handled by AI fanning out PRs to the `wkx-*` repos rather than by a template-update command. A reasonable reader would expect a templating tool here, so this deliberate omission is recorded to stop one being added by reflex.

_Source: design spec §5._
