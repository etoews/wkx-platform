# WKX Platform

The shared substrate (host, Caddy, infrastructure, deploy tooling) that runs personal projects in two homes: public-facing on AWS, private-facing on a home server. This glossary is the canonical ubiquitous language for the platform. Where a term has competing synonyms, the preferred term is defined and the rest are listed under `_Avoid_`.

## Language

### Deployable units and topology

**Platform**:
The shared substrate this repo builds: host, Caddy, infrastructure, and deploy tooling. The thing projects run *on*. In config, log, and data namespaces, `platform` occupies the `<service>` slot for host-level and substrate emissions (for example `/wkx/platform/<env>`), extending the Platform stack's borrowed `<service>-<env>` shape; no app Service may take the name.

**App**:
The umbrella term for one project and the service(s) it runs, taken as a whole, at the altitude where the project/service distinction does not matter ("the hello app"). One app is one Project (its repo), which defines one or more Services. Reach for Project or Service when the distinction matters.

**Project**:
One app's source repo, `wkx-<name>`, scaffolded from the reference project. The unit of source control and scaffolding: code, `compose.yml`, `caddy.snippet`, deploy workflow, issues, history. One per app. Distinct from a Compose project.

**Service**:
A single deployable unit: one main container (plus any sidecars). The `<service>` token names it across every runtime namespace (hostname, Compose project, SSM path, log group, data dir). The unit of deployment, routing, and operations. A project usually defines one service, but may define several; each is deployed once per env. Distinct from a Compose service: a Service is a main container with a hostname, not a sidecar.

**Compose project**:
The `<service>-<env>` namespace that isolates one service-env's containers, networks, and volumes, set via `docker compose -p` (for example `hello-prod`). Not the same thing as a Project (the `wkx-<name>` repo), despite the shared word.

**Compose service**:
Any container block in a `compose.yml`, in Docker's sense of the word, including sidecars such as a Postgres `db`. The platform Service is the main one (the container with the hostname); sidecars are additional Compose services in the same Compose project.

**Platform services**:
The always-on shared services: Caddy and the backup runner. Layer 3 of the stack. Each platform service occupies the `<service>` slot in config and data namespaces (`/wkx/caddy/<env>/...`, `/srv/data/caddy/<env>`) without being a Service: none has a hostname. The CloudWatch agent is not one: it is Layer 2 host tooling, installed and configured by host bootstrap.

**Platform stack**:
The platform services' own Compose project, `platform-<env>`, holding every platform service on a Host. Deliberately borrows the `<service>-<env>` shape without naming a Service.
_Avoid_: platform compose project

**Host**:
The single box that runs everything via Docker Compose: either the cloud Graviton EC2 instance or the home server.
_Avoid_: server, instance, node

**Home server**:
The on-prem Ubuntu (x86) box that runs the same Compose stack, reachable on the LAN only.

**Origin**:
The host as Cloudflare sees it. The only source the origin security group admits on 443 is Cloudflare's published IP ranges.

**Data volume**:
The persistent volume mounted at `/srv/data` on a Host, holding all Service data. It outlives the Host: replacing the box never touches it. The Host's root volume, by contrast, is disposable.
_Avoid_: EBS volume, disk, storage (ambiguous between root and data)

**platform user**:
The operating-system user on a Host that owns the Data volume and runs the Compose workloads. Created by host bootstrap on both the cloud Host and the Home server.
_Avoid_: service account, deploy user

**Reference project**:
The real, CI-tested working app under `template/` that new projects are copied from. There is no templating tool; copying plus name/port/hostname substitution is the mechanism.
_Avoid_: boilerplate, scaffold (the noun), cookiecutter

### Environments

**env**:
The deployment-environment slot present in every namespace. Always named explicitly, never defaulted.
_Avoid_: stage, environment (in resource names, spell it `env`)

**prod**:
The cloud production env. The only env whose public hostname hides the `-<env>` suffix (`hello.wingkongexchange.dev`, never `hello-prod...`).

**home**:
The on-prem env that runs on the home server.

**Preview env**:
An ephemeral per-PR or per-branch env (`pr-<N>`, `feat-<slug>`). Forward-compatible from day one; the workflow that creates them is deferred.
_Avoid_: staging

### Routing and domains

**Apps apex**:
`wingkongexchange.dev`, the shared parent domain that Mode-3 services live under as subdomains. Registered in M1.
_Avoid_: root domain, base domain

**Mode 1**:
First-class routing: a service on its own apex domain (`<APP_DOMAIN>`, a per-project placeholder, not yet registered).
_Avoid_: custom domain

**Mode 3**:
Second-class routing: a service on a subdomain of the apps apex. (Mode 2, path-based routing, was considered and rejected; it is not used.)

**Caddy snippet**:
The single Caddy host block a project contributes, aggregated by the platform at `/etc/caddy/Caddyfile.d/<service>-<env>.caddy` (flat directory; Caddy import globs allow a single wildcard, decided at M3).

**Edge network**:
The shared Docker network `wkx-edge` on a Host, created and named by the Platform stack. Caddy and every deployed Service attach to it; requests cross from Layer 3 to Layer 4 over it.
_Avoid_: proxy network, caddy network

**Edge alias**:
The network alias `<service>-<env>` a Service registers on the Edge network; the upstream address its Caddy snippet proxies to (for example `hello-prod`).

### Configuration and secrets

**Parameter**:
One SSM Parameter Store entry at `/wkx/<service>/<env>/<KEY>`, the unit of config for a Service in an env. `<KEY>` is uppercase snake case and becomes the variable name in the Env-file. Secrets are type `SecureString`; non-secret config is `String`. The type states sensitivity only; both render identically.
_Avoid_: SSM param, secret (as the umbrella term; not every Parameter is secret)

**Parameter namespace**:
The path prefix `/wkx/<service>/<env>/` that scopes one Service-env's Parameters. The render reads exactly this prefix, nothing deeper.
_Avoid_: parameter path, SSM namespace

**Env-file**:
The per-Service, per-env file at `/srv/secrets/<service>/<env>.env`, rendered from SSM Parameter Store at deploy time and consumed by a Compose service's `env_file:` directive, becoming the container's environment. Carries secrets and non-secret config alike. Regenerated on every deploy, never edited by hand, never committed; it lives on the disposable root volume, not the Data volume.
_Avoid_: dotenv, .env (ambiguous with the Env-file Interpolated), secrets file

**Env-file Interpolated**:
The gitignored `.env` beside a compose file, supplying `${VAR}` interpolation values (registry, image tags, `ENV`) to Compose itself. Hand-maintained on a Host, never contains secrets; its values shape the compose configuration and never enter a container's environment. In prose: "the interpolated env-file".
_Avoid_: .env (ambiguous with the Env-file), interpolation env

### Operational status

**Status**:
The three-word health vocabulary for a Service or alarm on any operational surface: up, stabilising, or down, paired with the plan symbols `+`, `~`, `−`. One word per state, no synonyms. Status is the operator's reading; a source system's own state (CloudWatch OK/ALARM/INSUFFICIENT_DATA, `docker compose ps` output) is always shown verbatim beside it, never softened or replaced. An alarm in ALARM says ALARM, whatever colour the board wears.

**up**:
Running as expected, within thresholds. Deliberately the same word Compose prints and the uptime column uses ("up 4 h 38 m"): one word, one meaning, everywhere. Symbol `+`.
_Avoid_: healthy, standing, OK (OK is the CloudWatch state, reported verbatim)

**stabilising**:
In motion toward up with no operator action owed: the credit bank refilling after a Host replacement, a Service warming after deploy. Attend only if it lingers past its expected window; a stabilising entry should always name that window. Symbol `~`.
_Avoid_: degraded, warning, changing, holding

**down**:
Not serving. Act now. Symbol `−`.
_Avoid_: fault, failed, outage, offline

**unlit**:
Nothing occupies this slot yet: the namespace is reserved and waiting (hello-home before M9, backup before M10). A presentation state, not a health state; absence, never failure. Takes no symbol.
_Avoid_: pending, inactive, missing
