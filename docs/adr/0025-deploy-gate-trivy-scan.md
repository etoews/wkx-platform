# The deploy gate is an in-pipeline Trivy scan, not the ECR scan-on-push

Status: accepted

The M6 pipeline gates a deploy on a Trivy image scan run in GitHub Actions with `--ignore-unfixed`, failing the job on high or critical findings that have a fix available. ECR scan-on-push stays enabled but informational: it never gates a deploy.

The gate moved to Trivy after an empirical discovery. No image pushed before M6 had ever actually been scanned by ECR, despite scan-on-push being set on the `wkx/caddy` and `wkx/hello` repositories since M3. The buildx default wraps each image in an OCI image index carrying a provenance attestation, and ECR silently refuses to scan an OCI index (it reports no findings rather than an error), so every "scan on push" result was an empty pass on an image that was never inspected. Gating on that result would have been a gate on nothing. Building without the attestation would restore ECR scanning, but the scan still runs after the push, so a failing image is already in the registry before the gate can react, and the result would follow the AWS scan cadence rather than the pipeline's.

Running Trivy in the job scans the exact artefact before it is deployed, on the pipeline's own clock, and `--ignore-unfixed` keeps the gate actionable by ignoring findings with no available fix (which would otherwise block every deploy on un-patchable base-image noise). ECR scan-on-push is left on because it is free and gives a second, registry-side record, but the deploy decision belongs to the in-pipeline scan. This reword replaces F-006's original "gate on the ECR scan-on-push results".

_Source: M6 design (2026-08-08); ROADMAP.md M6 (F-006)._
