# hello

The M3 smoke-test app: proves browser -> Cloudflare -> Caddy -> container.
Lives in the platform repo until M6 extracts it to `wkx-hello`; becomes the
ancestor of the reference project at M8.

- `src/app.py`: stdlib HTTP server on port 8000; responds with `MESSAGE`
  (default: "hello, wing kong exchange").
- `test.sh`: builds the image and probes it locally (default + override).
- Deploy (manual until M6): see §6 of the M3 design spec.
