# Codex Sandbox v2: Maintainer and Security Reference

## Security objective

The expected damage boundary for the networked runner is one deliberately
selected public or synthetic working tree, its scratch directory, its outbox,
its disposable caches, and its project-specific Codex login. The design does
not claim protection against Docker, kernel, or virtualization vulnerabilities.

The offline runner separates private-data access from Codex and outbound
communication. Human-controlled WSL remains the only promotion authority.

## Why v2 does not use Dev Containers as the boundary

VS Code Dev Containers can add mounts and sockets that are not declared in a
project's `devcontainer.json`. The previous deployment included a shared
`/vscode` volume and a WSLg Wayland socket. V2 creates containers directly with
Docker, verifies the final Docker configuration before start, and treats VS
Code only as a trusted editor before or after autonomous execution.

## Trusted and untrusted components

Trusted WSL components:

- `~/codex-sandbox-kit/bin/sandboxctl`;
- pinned Dockerfiles, root-owned container checks, and Codex policy;
- each project's `control` directory;
- Docker itself and the WSL/Linux kernel boundary;
- the human review and Git promotion process.

Untrusted during a networked run:

- the repository working tree and project instructions;
- dependencies, build scripts, tests, websites, fixtures, and tool output;
- all model-generated commands and files;
- outbox content produced by container code.

## Container creation and verification

The launcher uses `docker create`, not `docker run`. Before start, it verifies:

- privileged mode is false;
- the root filesystem is read-only;
- every Linux capability is dropped;
- no-new-privileges is active;
- the network mode matches the selected zone;
- there are no exposed devices or published ports;
- the complete mount destination/type/write-mode list exactly matches the
  expected allowlist.

The host report is written under the unmounted `control/logs` directory, so the
container cannot alter it. A second root-owned check runs inside the container.

## Networked runner mounts

- `/workspace`: selected repository, writable;
- `/workspace/.git`: nested read-only bind mount;
- `/agent/scratch`: public/synthetic scratch, writable;
- `/agent/outbox`: review output, writable;
- `/auth`: project-specific volume containing only the synchronized
  `auth.json` credential, writable;
- `/home/node/.codex`, `/home/node/.cache`, and `/tmp`: disposable tmpfs
  mounts.

There is no inbox, Docker socket, Windows drive, WSL home mount, SSH agent,
browser profile, VS Code volume, or WSLg socket.

## Offline runner mounts

- `/source`: current repository, read-only;
- `/agent/inbox`: selected private fixtures, read-only;
- `/agent/outbox`: review output, writable;
- `/workspace`: fresh tmpfs populated from `/source` on every invocation;
- `/home/node/.cache` and `/tmp`: disposable tmpfs mounts.

The container uses Docker network mode `none` and contains no Codex executable.
Project-specific dependencies should later be supplied through a separately
reviewed and locked offline image; this is required when migrating `aihealth`.

## Codex configuration

The image stores root-owned configuration at `/etc/codex/config.toml` and
root-owned constraints at `/etc/codex/requirements.toml`. The interactive
runtime uses `--strict-config` to fail on unknown keys. Codex 0.148 does not
support that flag on authentication or informational subcommands, so those
commands rely on the same root-owned configuration without the flag. Each
container receives a fresh tmpfs `CODEX_HOME`; a root-owned wrapper copies in
only `/auth/auth.json` and synchronizes only that file when the command exits.
Configuration, rules, sessions, logs, and caches cannot persist through the
authentication volume.

The requirements file constrains the approval/sandbox modes, disables Apps,
plugins, browser and computer-use surfaces, disables project/user hooks, and
prevents automatic CLI updates. The outer Docker boundary is still the primary
sandbox because the inner Codex sandbox is intentionally bypassed.

## Version policy

`versions.lock` records:

- the kit version;
- an immutable base-image digest;
- an exact Codex CLI version;
- npm integrity values for the wrapper and Linux x64 binary package;
- the local image tags.

Do not use `latest`, floating base tags without digests, or automatic Codex
updates. Upgrades are deliberate maintenance events:

1. Review the current official Codex configuration and CLI documentation.
2. Resolve the new npm version and package integrity values.
3. Resolve the new multi-platform base-image digest.
4. Change `versions.lock` in one reviewable commit.
5. Run `tests/static.sh`.
6. Rebuild both images.
7. Run `tests/smoke.sh` without invoking a model.
8. Authenticate a disposable project and run one tightly bounded model task
   only when a real end-to-end validation is justified.
9. Keep the previous image until the upgraded version is accepted.

## Authentication limitation

Codex must be able to use its ChatGPT credential, so a process with unrestricted
access inside the networked runner can potentially read that project-specific
credential. V2 reduces the blast radius by isolating authentication by project,
excluding every other credential, using device authorization, and providing
logout and volume-destruction commands. It does not claim to eliminate this
risk.

If stronger protection is required, the tradeoff is a restricted egress design
or a different execution model. Arbitrary public internet access and a secret
that is usable by the same unrestricted process cannot be treated as complete
credential isolation.

## Project customization

Trusted per-project settings live in
`~/agent-workspaces/<slug>/control/project.env`, outside every container. The
file supports only the documented fixed keys parsed by `sandboxctl`; it is not
sourced as shell code.

`control/protected-paths.txt` can add repository-relative nested read-only
mounts for trusted policy or supervisor files. This list is not a security
substitute for the root-owned kit controls.

Custom project images may be selected in `project.env`. Before migrating
`aihealth`, add a reviewed offline Dockerfile that installs its locked runtime
dependencies without network access at test time.

## Incident response

For a boundary-check failure, suspicious dependency, prompt-injection event, or
unexpected container behavior:

1. Stop and remove the task container.
2. Preserve the trusted host-side boundary report.
3. Review the repository and outbox from trusted WSL.
4. Run `sandboxctl logout <slug>` when possible.
5. Run `sandboxctl destroy-auth <slug> --yes`.
6. Discard disposable cache and task output.
7. Rebuild the pinned images if image integrity is in doubt.
8. Reauthenticate only after the cause is understood.

Never add privileged mode, `SYS_ADMIN`, an unconfined security profile, the
Docker socket, broad host mounts, or GUI/browser sockets as a workaround.
