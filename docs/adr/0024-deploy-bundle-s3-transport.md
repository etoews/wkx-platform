# Deploy artefacts travel as sha-addressed S3 bundles

Status: accepted

A deploy carries two kinds of artefact to the Host. The container image already travels through ECR. The deploy-time files (the compose file plus its `compose.cloud.yml` overlay, the Caddy snippet, the deploy script, and the M5 render script) travel as a tarball uploaded to a shared deploy bucket under a per-project, sha-addressed prefix (`deploy/<service>/<sha>/bundle.tar.gz`). The GitHub Actions job builds the bundle from the checked-out commit and calls `PutObject`; the `aws ssm send-command` invocation then passes only the bundle's key, and the on-box script pulls the bundle down, unpacks it, renders the Env-file, and runs `docker compose up -d`. Image and bundle share the same `<sha>`, so one commit fully describes a deploy.

Three alternatives were rejected. An inline send-command payload (the whole script and its files as SSM document parameters) runs into the send-command parameter size ceiling and buries multi-file orchestration in a JSON string that cannot be linted or tested. An app-repo clone on the Host would put git credentials on the box, widen its trust to every project repo, and couple a deploy to GitHub being reachable at deploy time. Baking the deploy files into the image folds platform-owned orchestration into the app image, so fixing the deploy script would force an app rebuild, and the platform could no longer ship a deploy-path change without every project rebuilding.

This adds one permission to the CI deploy role, so F-001's guard-rail wording changes: the role now gets ECR push, send-command, and `PutObject` on its own deploy-bucket prefix, never any state-bucket access. The prefix is scoped per project so one project's CI cannot write another's bundle, and the state bucket (which holds the DNS-01 token) stays entirely out of the role's reach.

_Source: M6 design (2026-08-08); ROADMAP.md M6 (F-001)._
