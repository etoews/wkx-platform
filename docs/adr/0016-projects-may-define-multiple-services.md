# Projects may define more than one service

Status: accepted

A project (one `wkx-<name>` repo) usually defines a single service, but it may define several. The runtime namespace model already accommodates this: each service carries its own `<service>` token across hostname, Compose project, SSM path, log group, and data dir, so multiple services in one repo do not collide. The reference project, the scaffold tool, and the platform-to-project contract are written for the common single-service case; a multi-service project is a deliberate per-project deviation, not the default.

Recorded because the naming patterns (one `<service>` per repo) read as a hard one-to-one rule, and a future reader would otherwise assume a repo can expose only one service. Keeping the door open avoids splitting naturally-cohesive services (for example a public site and its admin UI) into separate repos purely to satisfy tooling.

_Source: design conversation; relaxes the implicit one-service-per-project assumption in spec §4 and §5._
