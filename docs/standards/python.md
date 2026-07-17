# Python standards

Python here follows the machine-wide standards in `~/dev/etoews/python/PROJECT.md`: uv for deps and envs, ruff for lint and format, pytest for tests, ty for type checking, stdlib `logging`, `src/` layout, `pyproject.toml` as the single source of truth. This document is the distillation, recording which parts bind in this repo and where they stop. It expands the clause in [ADR 0022](../adr/0022-secrets-render-bash-aws-cli.md) that says Python under `tools/` is "uv-packaged with ruff, pytest, and ty". PROJECT.md keeps the full rationale and the copy-paste templates; the section references below point into it.

## Bash first

Python is not the default. ADR 0022 settled the order: a tool is bash plus the AWS CLI until it genuinely outgrows bash, and only then becomes Python. The revisit trigger is a tool outgrowing bash, not a preference for Python. The `wkx-scaffold` CLI (M8) is the likely first case.

## Two shapes

Every piece of Python here is one of two shapes, and the shape decides how much of the standard applies.

**Stdlib-only.** No third-party imports, no uv, no `pyproject.toml`. Runs under an interpreter that is already present: the Host's system `python3` for on-box scripts (`tools/secrets/render-env.py`), or the container base image for a dependency-free app (`hello/src/app.py`). ADR 0022 is why the shape exists, because the packaged alternative would have cost a pinned uv install in cloud-init, a PyPI dependency in the deploy path, and permanent dev-to-box interpreter drift. Hold the constraint deliberately: a single `uv add` in an on-box script changes the deploy path's dependency surface.

**uv-packaged.** The full PROJECT.md stack. This is what `tools/<tool>/` gets when a tool outgrows bash, and what a real app in a `wkx-<name>` repo gets. The `template/` reference project (M8) is uv-packaged; `hello` is its stdlib-only ancestor and crosses over when it is extracted (M6) and generalised (M8).

|                | Stdlib-only                                        | uv-packaged                                  |
|----------------|----------------------------------------------------|----------------------------------------------|
| Lives in       | on-box scripts, dependency-free containers         | `tools/<tool>/`, `wkx-*` app repos           |
| Dependencies   | none, ever                                         | `uv add`, `uv.lock` committed                |
| Layout         | one file beside its bash caller                    | `src/<pkg>/` plus `tests/`                   |
| Config         | none                                               | `pyproject.toml`                             |
| Lint, format   | `ruff check` / `ruff format` (global tool, no project config, so ruff's defaults apply) | `uv run ruff check --fix` / `uv run ruff format` |
| Tests          | the caller's harness (`tools/secrets/test.sh`)     | `uv run pytest`                              |
| Types          | annotated, no checker wired                        | `uv run ty check`, clean on every commit     |

## Stack (uv-packaged)

| Purpose         | Tool                       | Install                          |
|-----------------|----------------------------|----------------------------------|
| Deps and envs   | uv                         | machine-wide (MAC.md)            |
| Lint and format | ruff                       | `uv add --dev ruff`              |
| Tests           | pytest                     | `uv add --dev pytest pytest-cov` |
| Type check      | ty                         | `uv add --dev ty`                |
| Logging         | stdlib `logging`           | built in                         |
| CLI             | Typer, with `rich` output  | `uv add typer rich`              |
| Config          | pydantic-settings          | `uv add pydantic-settings`       |

Never `pip install`; `PIP_REQUIRE_VIRTUALENV=1` makes it fail anyway. Commit `pyproject.toml`, `uv.lock`, `.python-version`; gitignore `.venv/`. Declare lower bounds only (`httpx>=0.28`), because pinning is `uv.lock`'s job. ty is pre-1.0: if it blocks a legitimate typing pattern, swap that project to mypy and note the swap in its README (PROJECT.md §5).

## The bar, in both shapes

- **Typed signatures.** Every function and method carries parameter types and a return type, `-> None` included, in source and in tests. Modern syntax only: `list[int]`, `dict[str, X]`, `X | None`, never `typing.List` or `Optional`. Class attributes get annotations. `# type: ignore[rule]`, never a bare ignore.
- **Google-style docstrings** on every public module, class, and function. Document intent, not mechanics: preconditions the caller must meet, what "missing" means here, exceptions raised, non-obvious side effects (PROJECT.md §6).
- **Specific exceptions, translated at boundaries.** uv-packaged code defines a hierarchy in `exceptions.py` and catches third-party exceptions at the seam where it meets the external library, re-raising with `from e`. Never bare `except:`; `except ... pass` needs a one-line reason. A stdlib-only script fails closed with a non-zero exit and a message on stderr, which is the same discipline at a smaller scale (PROJECT.md §9).
- **stdlib `logging`, never `print()` for diagnostics.** Module-level `logger = logging.getLogger(__name__)`, never the root logger. Use `%`-style lazy formatting, not f-strings, so a filtered message costs nothing. Libraries add a `NullHandler` and configure nothing; applications configure once at the entry point (PROJECT.md §7, §14d).
- **Never log a secret.** No passwords, tokens, request or response bodies, PII. Log identifiers instead. `tools/secrets/render-env.py` is the worked example: stderr reports counts and key names, never values.

## Config and secrets on this platform

One typed config object, built once at the entry point, passed down explicitly. Nothing deep in the call stack reaches into `os.environ`; if a function needs a value it takes it as a parameter. uv-packaged apps use `pydantic-settings` (PROJECT.md §10): required fields have no default, so missing config fails at startup rather than at first use; `extra="forbid"` turns a typo'd variable into an error instead of a silent no-op; `SecretStr` wraps every secret, so `repr` and log output mask it by default and `.get_secret_value()` appears only at the point of use.

This platform is the "host's secret store" that PROJECT.md §10 defers to, which pins down four things a Python app here must know.

- **The SSM key name is the environment variable name, verbatim.** Terraform holds the Parameter at `/wkx/<service>/<env>/<KEY>`; `render-env.py` strips the prefix and requires the remainder to match `^[A-Z][A-Z0-9_]*$`. A project that sets `env_prefix = "NOTES_"` therefore needs its Parameter named `/wkx/notes/prod/NOTES_DATABASE_URL`.
- **`format: raw` means no interpolation.** Compose injects the rendered Env-file with `env_file` long syntax (ADR 0022), so the value the operator put in the Parameter is the value the process sees. No shell quoting, no `${}` expansion.
- **`.env` is local dev only,** gitignored, never baked into an image. Commit `.env.example` with every key present and placeholder values, as the documented contract for what the app needs to run.
- **A container cannot reach the instance role.** IMDS hop limit is 1 (ADR 0023), so `boto3` inside a container gets no credentials from the instance profile and no silent fallback to the Host's role. An app that genuinely needs an AWS API needs its own credentials path, chosen deliberately.

## Logging on this platform

Container stdout and stderr ship to the `/wkx/<service>/<env>` log group through Docker's `awslogs` driver (ADR 0020), so an app logs to stdout and configures nothing else: no CloudWatch handler, no file handler, no rotation. `_logging.py` (PROJECT.md §14d) is the template, and `LOG_FORMAT=json` is the setting to use on the box, since Logs Insights discovers JSON fields without a parse expression.

## ARM64

Containers target `linux/arm64` by default (ADR 0005). Prefer dependencies that publish aarch64 wheels. Anything that falls back to a source build drags a compiler toolchain into the builder stage and slows every image build, so check the wheel situation before adding a dependency rather than after the build slows down.

## CI and gates

M6 brings GitHub Actions to the `wkx-*` repos. A uv-packaged project runs the same checks in CI that a local pre-commit hook runs (PROJECT.md §11, §14c):

```
uv sync --locked            # fails on a stale lockfile
uv run ruff check           # no --fix in CI
uv run ruff format --check
uv run ty check
uv run pytest
```

`uv python install` with no version argument honours `.python-version`, so CI needs no edit when a project's Python version moves. Pre-commit is a fast local gate that can be skipped (`git commit -n`), so CI stays the source of truth; run the same tools in both and do not let them drift. Nothing in this repo needs pre-commit until `tools/` gains its first uv package. Renovate (M7) covers uv lock files: minor and patch auto-merge on green CI, majors stay manual.

## What does not carry over

`~/dev/etoews/python/MAC.md` is one-time machine setup and has no bearing on the repo. PROJECT.md's optional-dependency extras, semver bumps, and publishing guidance are for libraries with downstream consumers; the tools here are unpublished internal ones, where `0.0.1` forever is fine. Coverage stays ungated until a suite is mature, so the tests chase bugs rather than the metric.

_Source: `~/dev/etoews/python/PROJECT.md`, distilled 2026-07-17. Expands ADR 0022._
