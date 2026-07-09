#!/usr/bin/env bash
# Tests for the Env-file render (ADR 0022): transform first, wrapper below.
# Usage: ./test.sh   (no AWS access needed; aws is stubbed)
set -uo pipefail
cd "$(dirname "$0")"

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Portable file-mode helper (macOS and Linux).
perms_of() { stat -f%Lp "$1" 2>/dev/null || stat -c%a "$1"; }

# ---------- transform: render-env.py ----------

json_ok='{"Parameters":[
  {"Name":"/wkx/hello/prod/MESSAGE","Value":"kia ora","Type":"String"},
  {"Name":"/wkx/hello/prod/API_KEY","Value":"s3cr3t$#x=\"q\"","Type":"SecureString"}]}'
out=$(printf '%s' "$json_ok" | python3 render-env.py /wkx/hello/prod/ 2>/dev/null)
expected=$(printf 'API_KEY=s3cr3t$#x="q"\nMESSAGE=kia ora')
[ "$out" = "$expected" ] && ok || bad "happy path: sorted, raw values preserved"

out=$(printf '{"Parameters":[]}' | python3 render-env.py /wkx/hello/prod/ 2>"$tmp/err")
{ [ -z "$out" ] && grep -q 'no Parameters' "$tmp/err"; } && ok || bad "empty namespace: empty output plus warning"

printf 'not json' | python3 render-env.py /wkx/hello/prod/ 2>/dev/null && bad "invalid JSON accepted" || ok

json_nl='{"Parameters":[{"Name":"/wkx/hello/prod/PEM","Value":"a\nb","Type":"SecureString"}]}'
printf '%s' "$json_nl" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "newline value accepted" || ok

json_ws='{"Parameters":[{"Name":"/wkx/hello/prod/PAD","Value":" padded ","Type":"String"}]}'
printf '%s' "$json_ws" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "padded value accepted" || ok

json_low='{"Parameters":[{"Name":"/wkx/hello/prod/message","Value":"x","Type":"String"}]}'
printf '%s' "$json_low" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "lowercase key accepted" || ok

json_nest='{"Parameters":[{"Name":"/wkx/hello/prod/db/PASSWORD","Value":"x","Type":"String"}]}'
printf '%s' "$json_nest" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "nested key accepted" || ok

json_out='{"Parameters":[{"Name":"/wkx/other/prod/KEY","Value":"x","Type":"String"}]}'
printf '%s' "$json_out" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "outside-prefix name accepted" || ok

printf '%s' "$json_ok" | python3 render-env.py /wkx/hello/prod/ 2>&1 >/dev/null | grep -q 's3cr3t' \
  && bad "stderr leaked a value" || ok

echo "transform: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
