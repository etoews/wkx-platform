# WKX Platform

The shared substrate (host, Caddy, infrastructure, deploy tooling) that runs personal projects in two homes: public-facing on AWS, private-facing on a home server. This glossary is the canonical ubiquitous language for the platform. Where a term has competing synonyms, the preferred term is defined and the rest are listed under `_Avoid_`.

## Language

### Deployable units and topology

**Platform**:
The shared substrate this repo builds: host, Caddy, infrastructure, and deploy tooling. The thing projects run *on*.

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
The always-on shared services: Caddy, the CloudWatch agent, and the backup runner. Layer 3 of the stack.

**Host**:
The single box that runs everything via Docker Compose: either the cloud Graviton EC2 instance or the home server.
_Avoid_: server, instance, node

**Home server**:
The on-prem Ubuntu (x86) box that runs the same Compose stack, reachable on the LAN only.

**Origin**:
The host as Cloudflare sees it. The only source the origin security group admits on 443 is Cloudflare's published IP ranges.

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
The single Caddy host block a project contributes, aggregated by the platform at `/etc/caddy/Caddyfile.d/<service>/<env>.caddy`.
