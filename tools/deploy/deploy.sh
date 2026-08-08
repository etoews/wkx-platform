#!/usr/bin/env bash
# Turn a sha-addressed Deploy bundle plus an image tag into a verified,
# serving Service (design spec §4; ADRs 0006, 0022, 0024). Fails closed at
# every step: a missing bundle, a compose file with no healthcheck, a failed
# Env-file render, an unhealthy container, or a failed probe all exit non-zero
# so the RunCommand and the workflow go red.
#
# Usage: deploy.sh --service <service> --env <env> --tag <sha>
# env is always explicit, never defaulted (ADR 0006): prod, or a pr-<number>
# preview env. tag is the image sha, which is also the bundle's sha.
set -euo pipefail

region="ap-southeast-2"          # single region (invariant 6)
apps_apex="wingkongexchange.dev" # apps apex domain (design spec §6)
platform_project="platform-prod" # the Platform stack that runs Caddy

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Test-only seams, mirroring render-env.sh's --output. Production takes the
# defaults; test.sh points these at a temp tree so it needs no AWS, Docker,
# network, or write access to /etc and /srv.
render_script="${WKX_RENDER_SCRIPT:-$here/../secrets/render-env.sh}"
caddy_dir="${WKX_CADDY_DIR:-/etc/caddy/Caddyfile.d}"
health_timeout="${WKX_HEALTH_TIMEOUT:-120}"
health_interval="${WKX_HEALTH_INTERVAL:-3}"

usage() {
  cat >&2 <<'EOF'
usage: deploy.sh --service <service> --env <env> --tag <sha>
  --service, --env, and --tag are all required; nothing is defaulted (ADR 0006).
  valid env patterns: prod | pr-<number>
EOF
  exit 2
}

service='' env='' tag=''
while [ $# -gt 0 ]; do
  case "$1" in
    --service) service="${2:?}"; shift 2 ;;
    --env)     env="${2:?}"; shift 2 ;;
    --tag)     tag="${2:?}"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$service" ] && [ -n "$env" ] && [ -n "$tag" ] || usage

# service and env build filesystem paths, an SSM prefix, and a hostname; tag
# builds an S3 key and an image ref. Shape-validate to block traversal (same
# idea as render-env.sh, grill decision 2026-07-10).
name_shape='^[a-z][a-z0-9-]*$'
tag_shape='^[A-Za-z0-9][A-Za-z0-9._-]*$'
[[ "$service" =~ $name_shape ]] || { echo "deploy: invalid --service '$service'" >&2; exit 2; }
[[ "$env" =~ $name_shape ]]     || { echo "deploy: invalid --env '$env'" >&2; exit 2; }
[[ "$tag" =~ $tag_shape ]]      || { echo "deploy: invalid --tag '$tag'" >&2; exit 2; }

# The deploy bucket and ECR registry are derived from the caller's account, the
# same pattern the Terraform uses (infra/aws/deploy.tf), so no literal account
# id lives in the script. get-caller-identity is read-only.
account=$(aws sts get-caller-identity --query Account --output text)
registry="${account}.dkr.ecr.${region}.amazonaws.com"
bucket="wkx-deploy-${account}"
project="${service}-${env}"

# prod hides the env; every other env carries the suffix (design spec §6).
if [ "$env" = prod ]; then
  hostname="${service}.${apps_apex}"
else
  hostname="${service}-${env}.${apps_apex}"
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# 1. Fetch the sha-addressed Deploy bundle (ADR 0024). A non-zero aws exit
# (missing bundle, no credentials) aborts under set -e before anything starts.
aws s3 cp "s3://${bucket}/deploy/${service}/${tag}/bundle.tar.gz" "$workdir/bundle.tar.gz"
tar xzf "$workdir/bundle.tar.gz" -C "$workdir"
cd "$workdir"

# 2. Healthcheck gate. A Service with no container healthcheck cannot be
# verified, so refuse it before starting, rendering, or wiring anything.
[ -f compose.yml ] || { echo "deploy: bundle has no compose.yml; aborting" >&2; exit 1; }
if ! grep -Eq '^[[:space:]]*healthcheck:' compose.yml; then
  echo "deploy: compose.yml declares no healthcheck; aborting before start" >&2
  exit 1
fi

# 3. Render the Env-file from SSM (ADR 0022), verbatim. Under set -e any
# non-zero render exit aborts the deploy; never branch on its exit code.
"$render_script" --service "$service" --env "$env"

# 4. Start the Service. The interpolation values come from here, never from a
# hand-maintained file on the Host: the registry (account + region), the image
# tag, and the env the compose file reads. The per-service tag var matches the
# compose convention (hello -> HELLO_TAG).
tag_var="$(printf '%s' "$service" | tr 'a-z-' 'A-Z_')_TAG"
export ECR_REGISTRY="$registry"
export "${tag_var}=${tag}"
export ENV="$env"
docker compose -f compose.yml -f compose.cloud.yml -p "$project" up -d

# 5. Render the Caddy snippet with the documented hostname, drop it, reload
# Caddy. Recreate the snippet dir first in case a Host replacement removed it.
mkdir -p "$caddy_dir"
snippet="$caddy_dir/${project}.caddy"
sed -e "s|<hostname>|${hostname}|g" -e "s|<env>|${env}|g" caddy.snippet > "$snippet"

# Reload Caddy the same way platform/ does (caddy reload --config ...). The
# caddy container is found by its Compose labels, so this needs neither the
# platform compose file in reach nor a brittle raw container name (ADR 0019).
caddy_cid=$(docker ps -q \
  --filter "label=com.docker.compose.project=${platform_project}" \
  --filter "label=com.docker.compose.service=caddy" | head -n1)
[ -n "$caddy_cid" ] || { echo "deploy: no running caddy container in ${platform_project}" >&2; exit 1; }
docker exec "$caddy_cid" caddy reload --config /etc/caddy/Caddyfile

# 6. Verify. Wait for the container to report healthy (bounded), then probe the
# Service hostname. Either failure exits non-zero so the deploy goes red.
cid=$(docker compose -f compose.yml -f compose.cloud.yml -p "$project" ps -q | head -n1)
[ -n "$cid" ] || { echo "deploy: no container for ${project}" >&2; exit 1; }

deadline=$((SECONDS + health_timeout))
while :; do
  status=$(docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo unknown)
  case "$status" in
    healthy) break ;;
    unhealthy) echo "deploy: ${project} reported unhealthy" >&2; exit 1 ;;
  esac
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "deploy: ${project} not healthy within ${health_timeout}s (last: ${status})" >&2
    exit 1
  fi
  sleep "$health_interval"
done

# Probe the Service hostname over TLS, resolved to the local Caddy so the check
# exercises Caddy's routing without depending on Cloudflare or the origin SG.
if ! curl -fsS -o /dev/null --resolve "${hostname}:443:127.0.0.1" "https://${hostname}/"; then
  echo "deploy: probe of https://${hostname}/ failed" >&2
  exit 1
fi

echo "deploy: ${project} healthy and serving at https://${hostname}/" >&2
