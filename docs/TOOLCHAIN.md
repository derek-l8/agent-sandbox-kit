# Python and shared tools

Kit 3.2.0 makes Python 3.14.7 the default in each agent image. `python` and
`python3` resolve to the root-owned interpreter under `/opt/python`. The distro
interpreter, when present, stays in `/usr/bin`; operating-system tools are not
redirected to Python 3.14. `uv` 0.12.18 is installed from a SHA-256-verified
official PyPI wheel. The exact pins are in `versions.lock`.

The shared installer also provides Git, Bash, coreutils, findutils, diff/patch,
rg/fd, curl/CA certificates, jq, file, archive utilities, C/C++ compilers, make,
pkg-config, and Poppler (`pdftotext`, `pdftoppm`). Node.js/npm come from the
digest-pinned base image. This does not install browsers, OCR, FFmpeg, GPU
drivers, PyTorch, or project-specific Python/JavaScript libraries.

## Python projects

Run these commands **inside a task container**, in `/workspace`:

```bash
# For a uv project, respect its declared Python version and lockfile.
uv sync --locked
uv run python --version

# For a requirements.txt project:
uv venv --python 3.14 /data/venv
uv pip install --python /data/venv/bin/python -r requirements.txt
/data/venv/bin/python -m your_module
```

`UV_PROJECT_ENVIRONMENT=/data/venv` puts uv project environments outside Git.
This does not activate that environment for bare `python` commands: use
`uv run`, its absolute interpreter path, or `source /data/venv/bin/activate`.
For multiple independent Python projects in one workspace, select distinct
paths with `UV_PROJECT_ENVIRONMENT=/data/another-venv uv sync`.

An older project can request another version through `.python-version`, its
`requires-python` declaration, or `uv venv --python 3.13 /data/older-venv`.
Additional managed interpreters are downloaded into `/data/python`; they are
persistent and writable by the agent. Nothing automatically migrates an
existing project or changes its version declarations.

`uv pip` does not require pip inside the target environment. If a project
specifically invokes `python -m pip`, bootstrap it without downloading pip:

```bash
/data/venv/bin/python -m ensurepip --default-pip
/data/venv/bin/python -m pip install -r requirements.txt
```

The bundled interpreter exposes pip/pip3 for compatibility, but it retains
the externally-managed marker and is read-only in sessions. Install into a
virtual environment rather than the image's system environment.

## Storage and boundary

| Contents | Location | Lifetime |
| --- | --- | --- |
| Default Python and shared binaries | `/opt/python`, system binary directories | Read-only image |
| Project environment | `/data/venv` | Persistent, outside Git |
| Extra uv-managed Python versions | `/data/python` | Persistent, outside Git |
| `uv tool install` environments and commands | `/data/uv-tools`, `/data/bin` | Persistent, outside Git |
| uv/npm/pip caches | `/home/node/.cache` | Disposable tmpfs |

Invoke installed uv tools by `/data/bin/<command>` or explicitly add that
directory to your session's PATH. Compilers should write executable outputs
under `/workspace` or `/data`: `/tmp` intentionally remains non-executable.
Authentication-only containers do not mount `/data` and are not development
environments.

No host folders, credentials, devices, services, or ports are added. Downloads
and dependency execution remain possible in the networked sandbox. Tools do
not make readable data confidential from the agent or prevent network uploads.

## Builds and validation

`container/install-toolchain.sh` is a build-time installer shared by all three
Dockerfiles. The pinned uv release supplies Python download/checksum metadata.
Debian utilities use the configured signed Bookworm repositories: their patch
versions can change on an uncached build. The image records installed Debian
versions in `/usr/local/share/agent-sandbox-packages.txt`; this is not a claim
of fully reproducible OS packages. Update the base and package builds regularly.

`bash tests/smoke-toolchain.sh` exercises all three agents without credentials:
Python stdlib imports, uv/pip local-wheel installation, persistent virtualenvs,
an older interpreter override, disposable caches, C/C++ compilation and
execution, searches, archives, and actual PDF extraction/rendering. The other
smoke suites verify the unchanged agent boundaries. These checks do not prove
that an arbitrary project or PyTorch/CUDA combination supports Python 3.14.
