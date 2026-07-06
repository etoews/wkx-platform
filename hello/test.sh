#!/usr/bin/env bash
# Build-and-probe test for hello. Usage: ./test.sh
set -euo pipefail
cd "$(dirname "$0")"

docker build --platform linux/arm64 -q -t wkx-hello-test .
docker rm -f wkx-hello-test-run >/dev/null 2>&1 || true
docker run -d --rm --name wkx-hello-test-run -p 127.0.0.1:18000:8000 \
  --platform linux/arm64 wkx-hello-test
trap 'docker rm -f wkx-hello-test-run >/dev/null' EXIT
sleep 2

code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18000/)
[ "$code" = "200" ] || { echo "FAIL: expected 200, got $code"; exit 1; }
curl -s http://127.0.0.1:18000/ | grep -q 'hello, wing kong exchange' \
  || { echo "FAIL: default MESSAGE missing from body"; exit 1; }

docker rm -f wkx-hello-test-run >/dev/null
docker run -d --rm --name wkx-hello-test-run -p 127.0.0.1:18000:8000 \
  -e MESSAGE="kia ora" --platform linux/arm64 wkx-hello-test
sleep 2
curl -s http://127.0.0.1:18000/ | grep -q 'kia ora' \
  || { echo "FAIL: MESSAGE env override not honoured"; exit 1; }

docker rm -f wkx-hello-test-run >/dev/null
docker run -d --rm --name wkx-hello-test-run -p 127.0.0.1:18000:8000 \
  -e MESSAGE='<script>alert(1)</script>' --platform linux/arm64 wkx-hello-test
sleep 2
body=$(curl -s http://127.0.0.1:18000/)
echo "$body" | grep -q '&lt;script&gt;alert(1)&lt;/script&gt;' \
  || { echo "FAIL: MESSAGE not HTML-escaped in body"; exit 1; }
echo "$body" | grep -q '<script>' \
  && { echo "FAIL: raw MESSAGE markup reached the body"; exit 1; }

echo PASS
