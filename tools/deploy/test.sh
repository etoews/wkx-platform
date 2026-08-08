#!/usr/bin/env bash
# shellcheck disable=SC2015
# Tests for the fail-closed deploy (design spec §4; ADRs 0006, 0022, 0024).
# Usage: ./test.sh   (no AWS, Docker, or network needed; all are stubbed)
# Note: SC2015 disabled because ok() and bad() don't exit, so the A && B || C
# form is the intended test-assertion idiom (as in tools/secrets/test.sh).
set -uo pipefail
cd "$(dirname "$0")" || exit

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ---------- stubbed PATH: aws, docker, curl, and the render script ----------

mkdir -p "$tmp/bin"

# aws: sts echoes a fake account; s3 cp copies the fixture bundle to its dst,
# or fails when BUNDLE_FAIL is set. Every call is logged to $CALLS.
cat > "$tmp/bin/aws" <<'STUB'
#!/usr/bin/env bash
echo "aws $*" >> "$CALLS"
case "$1" in
  sts) echo "000000000000" ;;
  s3)
    [ -n "${BUNDLE_FAIL:-}" ] && exit 1
    for a in "$@"; do dst="$a"; done   # last positional is the destination
    cp "$BUNDLE_FIXTURE" "$dst" ;;
  *) : ;;
esac
STUB

# docker: compose up succeeds (or fails on DOCKER_UP_FAIL); compose ps and
# docker ps echo fake ids; inspect echoes HEALTH_STATUS; exec is a no-op.
cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$CALLS"
case "$1" in
  inspect) echo "${HEALTH_STATUS:-healthy}" ;;
  ps)      echo "caddycid456" ;;
  exec)    : ;;
  compose)
    for a in "$@"; do
      case "$a" in
        up) [ -n "${DOCKER_UP_FAIL:-}" ] && exit 1; exit 0 ;;
        ps) echo "webcid123"; exit 0 ;;
      esac
    done ;;
esac
STUB

# curl: the probe. Fails on CURL_FAIL, otherwise succeeds.
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$CALLS"
[ -n "${CURL_FAIL:-}" ] && exit 22
exit 0
STUB

# render-env stand-in: fails on RENDER_FAIL, otherwise succeeds.
cat > "$tmp/bin/render-stub" <<'STUB'
#!/usr/bin/env bash
echo "render $*" >> "$CALLS"
[ -n "${RENDER_FAIL:-}" ] && exit 1
exit 0
STUB

chmod +x "$tmp/bin/aws" "$tmp/bin/docker" "$tmp/bin/curl" "$tmp/bin/render-stub"

# ---------- fixture bundles: with and without a healthcheck ----------

snippet=$'<hostname> {\n\treverse_proxy hello-<env>:8000\n}\n'
cloud=$'services:\n  web:\n    logging:\n      driver: awslogs\n'

mkdir -p "$tmp/hc" "$tmp/nohc"

cat > "$tmp/hc/compose.yml" <<'YML'
services:
  web:
    image: ${ECR_REGISTRY:?}/wkx/hello:${HELLO_TAG:?}
    healthcheck:
      test: ["CMD", "true"]
    networks:
      wkx-edge:
        aliases: ["hello-${ENV:?}"]
networks:
  wkx-edge:
    external: true
YML
printf '%s' "$snippet" > "$tmp/hc/caddy.snippet"
printf '%s' "$cloud"   > "$tmp/hc/compose.cloud.yml"

cat > "$tmp/nohc/compose.yml" <<'YML'
services:
  web:
    image: ${ECR_REGISTRY:?}/wkx/hello:${HELLO_TAG:?}
    networks:
      wkx-edge:
        aliases: ["hello-${ENV:?}"]
networks:
  wkx-edge:
    external: true
YML
printf '%s' "$snippet" > "$tmp/nohc/caddy.snippet"
printf '%s' "$cloud"   > "$tmp/nohc/compose.cloud.yml"

tar czf "$tmp/bundle-hc.tar.gz"   -C "$tmp/hc"   .
tar czf "$tmp/bundle-nohc.tar.gz" -C "$tmp/nohc" .

# ---------- test harness helpers ----------

# Common environment for a deploy run. Per-test switches (BUNDLE_FAIL,
# RENDER_FAIL, HEALTH_STATUS, CURL_FAIL, DOCKER_UP_FAIL, BUNDLE_FIXTURE,
# WKX_CADDY_DIR) are exported by the caller before invoking run_deploy.
run_deploy() {
  : > "$tmp/calls"
  PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" \
    WKX_RENDER_SCRIPT="$tmp/bin/render-stub" \
    WKX_HEALTH_TIMEOUT="${WKX_HEALTH_TIMEOUT:-2}" WKX_HEALTH_INTERVAL="${WKX_HEALTH_INTERVAL:-1}" \
    ./deploy.sh "$@"
}
called()     { grep -q "$1" "$tmp/calls"; }
not_called() { ! grep -q "$1" "$tmp/calls"; }

# ---------- required args, nothing defaulted (ADR 0006) ----------

err=$(BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" run_deploy --service hello --tag abc123 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q 'prod' && printf '%s' "$err" | grep -q 'pr-'; } \
  && ok || bad "missing --env exits non-zero and prints valid env patterns"

BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" run_deploy --env prod --tag abc123 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok || bad "missing --service exits non-zero"

BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" run_deploy --service hello --env prod >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok || bad "missing --tag exits non-zero"

WKX_CADDY_DIR="$tmp/caddy-traversal" BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service '../etc' --env prod --tag abc123 >/dev/null 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && not_called 'docker compose.*up'; } \
  && ok || bad "traversal --service rejected before anything starts"

# ---------- fail-closed fetch and healthcheck gate ----------

WKX_CADDY_DIR="$tmp/caddy-bundlefail" BUNDLE_FAIL=1 BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && [ ! -e "$tmp/caddy-bundlefail/hello-prod.caddy" ] \
  && not_called 'docker compose.*up' && not_called '^render '; } \
  && ok || bad "bundle fetch failure aborts before starting"

WKX_CADDY_DIR="$tmp/caddy-nohc" BUNDLE_FIXTURE="$tmp/bundle-nohc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && [ ! -e "$tmp/caddy-nohc/hello-prod.caddy" ] \
  && not_called 'docker compose.*up' && not_called '^render '; } \
  && ok || bad "compose with no healthcheck aborts before start (no render, no up)"

# ---------- render failure propagates ----------

WKX_CADDY_DIR="$tmp/caddy-renderfail" RENDER_FAIL=1 BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && called '^render ' && not_called 'docker compose.*up'; } \
  && ok || bad "render failure propagates to a failed deploy; up not reached"

# ---------- snippet substitution: documented hostname forms ----------

WKX_CADDY_DIR="$tmp/caddy-prod" HEALTH_STATUS=healthy BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
snip="$tmp/caddy-prod/hello-prod.caddy"
{ [ "$rc" -eq 0 ] && grep -qF 'hello.wingkongexchange.dev' "$snip" \
  && ! grep -qF 'hello-prod.wingkongexchange.dev' "$snip"; } \
  && ok || bad "prod snippet uses <service>.apex, hiding the env suffix"

WKX_CADDY_DIR="$tmp/caddy-pr" HEALTH_STATUS=healthy BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env pr-42 --tag abc123 >/dev/null 2>&1; rc=$?
snip="$tmp/caddy-pr/hello-pr-42.caddy"
{ [ "$rc" -eq 0 ] && grep -qF 'hello-pr-42.wingkongexchange.dev' "$snip"; } \
  && ok || bad "non-prod snippet includes the <service>-<env> suffix"

# ---------- happy path reaches up, caddy reload, and probe ----------

WKX_CADDY_DIR="$tmp/caddy-happy" HEALTH_STATUS=healthy BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && called 'docker compose.*up' && called 'docker exec.*caddy reload' \
  && called '^curl '; } \
  && ok || bad "happy path runs compose up, caddy reload, and the probe"

# ---------- verification failure propagates ----------

WKX_CADDY_DIR="$tmp/caddy-unhealthy" HEALTH_STATUS=unhealthy BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok || bad "unhealthy container fails the deploy"

WKX_CADDY_DIR="$tmp/caddy-timeout" HEALTH_STATUS=starting WKX_HEALTH_TIMEOUT=1 WKX_HEALTH_INTERVAL=1 \
  BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok || bad "health wait timeout fails the deploy"

WKX_CADDY_DIR="$tmp/caddy-probefail" HEALTH_STATUS=healthy CURL_FAIL=1 BUNDLE_FIXTURE="$tmp/bundle-hc.tar.gz" \
  run_deploy --service hello --env prod --tag abc123 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok || bad "failed probe fails the deploy"

echo "total: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
