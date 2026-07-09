# tools/secrets

Renders a Service's Env-file from its Parameter namespace (ADR 0022):
`/wkx/<service>/<env>/<KEY>` in SSM Parameter Store becomes
`/srv/secrets/<service>/<env>.env` (0600, atomic, fail closed).

## Render

```bash
tools/secrets/render-env.sh --service hello --env prod
```

Both flags are required; there are no defaults (ADR 0006). Values are
written raw and consumed by Compose with `format: raw`, so no quoting or
interpolation applies. Runs anywhere the aws-cli has credentials: the
Host (instance role), a laptop, or the home server (M9).

## Set a Parameter

Secrets are `SecureString`; non-secret config is `String`. Keys are
UPPER_SNAKE_CASE. Tag every Parameter.

```bash
aws ssm put-parameter --name /wkx/<service>/<env>/<KEY> --type SecureString --value '<value>'
aws ssm add-tags-to-resource --resource-type Parameter --resource-id /wkx/<service>/<env>/<KEY> \
  --tags Key=Project,Value=wkx Key=Service,Value=<service> Key=Env,Value=<env>
```

To update: add `--overwrite` to `put-parameter` (tags persist). Values
must be single-line with no leading or trailing whitespace; the render
aborts otherwise. Then re-render and `docker compose up -d` (Compose
recreates the container when the Env-file content changed).

## Failure modes

The render fails closed and leaves no partial file. Common aborts: a key
that is not UPPER_SNAKE_CASE, a Parameter nested deeper than
`<namespace>/<KEY>`, a multi-line value, aws-cli errors. Zero Parameters
is not an error: an empty Env-file is rendered with a stderr warning.

## Tests

```bash
tools/secrets/test.sh    # stubbed aws; no AWS access needed
shellcheck tools/secrets/render-env.sh tools/secrets/test.sh
```
