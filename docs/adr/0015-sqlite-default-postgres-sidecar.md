# SQLite by default, Postgres as an opt-in sidecar, no shared platform Postgres

Status: accepted

Apps default to SQLite (a file on the EBS data volume). Postgres is opt-in per project, running as a sidecar container within that service's Compose project. There is no shared platform-level Postgres. A shared database was rejected deliberately to avoid blast-radius coupling (one app's load or migration cannot affect another) and backup entanglement (each service's data backs up independently under `/srv/data/<service>/<env>`). The trade-off is no cross-app SQL joins and a Postgres container per app that needs one. This is also why there is no RDS (see ADR-0002).

_Source: design spec §8.1._
