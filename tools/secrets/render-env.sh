#!/usr/bin/env bash
# Render a Service's Env-file from its Parameter namespace (ADR 0022).
# Usage: render-env.sh --service <service> --env <env> [--output <path>]
# Reads /wkx/<service>/<env>/ and writes /srv/secrets/<service>/<env>.env
# (0600, atomic; dir 0700). Fail closed; never logs values. --output is
# for tests only. env is always explicit, never defaulted (ADR 0006).
set -euo pipefail

usage() {
  echo "usage: render-env.sh --service <service> --env <env> [--output <path>]" >&2
  exit 2
}

service='' env='' output=''
while [ $# -gt 0 ]; do
  case "$1" in
    --service) service="${2:?}"; shift 2 ;;
    --env)     env="${2:?}"; shift 2 ;;
    --output)  output="${2:?}"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$service" ] && [ -n "$env" ] || usage

# Both values build the SSM path and the filesystem path: shape-validate
# to block traversal (grill decision, 2026-07-10).
shape='^[a-z][a-z0-9-]*$'
[[ "$service" =~ $shape ]] || { echo "render-env: invalid --service '$service'" >&2; exit 2; }
[[ "$env" =~ $shape ]] || { echo "render-env: invalid --env '$env'" >&2; exit 2; }

prefix="/wkx/${service}/${env}/"
[ -n "$output" ] || output="/srv/secrets/${service}/${env}.env"
outdir=$(dirname "$output")
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

umask 077
mkdir -p "$outdir"

tmpfile=$(mktemp "$outdir/.render-env.XXXXXX")
trap 'rm -f "$tmpfile"' EXIT

# --recursive so nested Parameters reach the transform and abort loudly
# instead of being silently omitted.
aws ssm get-parameters-by-path \
  --path "$prefix" --recursive --with-decryption --output json \
  | python3 "$here/render-env.py" "$prefix" > "$tmpfile"

mv "$tmpfile" "$output"
trap - EXIT
echo "render-env: wrote $output" >&2
