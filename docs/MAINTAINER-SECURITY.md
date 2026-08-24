# Maintainer and Security Reference

These are implementation notes for the Agent Sandbox Kit container boundary.
The project is experimental, unaudited, and intended for personal, reviewed
repositories.

## CLI and adapter boundary

`bin/sbx` performs only allowlisted agent/action translation and delegates to
`bin/sandboxctl`. The explicit registry under `adapters/` holds agent identity,
image/version keys, executable, authentication strategy, validation routine,
and compatibility command routes. It cannot supply Docker arguments.

The shared launcher retains ownership of isolation flags, allowed mounts and
their post-create verification, resources, locking, cleanup, and protected
paths. Adding an agent therefore requires launcher and security review, not
only an adapter file. See [Adding an Agent](ADDING-AN-AGENT.md).

## Security objective

The expected damage boundary for the networked runner is one deliberately
selected public or synthetic working tree, its scratch directory, its outbox,
its disposable caches, and its project-specific Codex login. The design does
not claim protection against Docker, kernel, or virtualization vulnerabilities.

The offline runner separates private-data access from Codex and outbound
communication. The intended workflow performs review and Git promotion from
WSL.

## Why the kit does not use Dev Containers as the boundary

VS Code Dev Containers can add mounts and sockets that are not declared in a
project's `devcontainer.json`. The kit instead creates containers directly
with Docker, verifies the final Docker configuration before start, and treats
VS Code only as a trusted editor before or after autonomous execution.

## Trusted and untrusted components

Trusted WSL components:

- the reviewed checkout's `bin/sandboxctl` launcher;
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
- `/auth`: project-specific authentication volume, mounted read-only for
  task, shell, and exec sessions;
- `/home/node/.codex`, `/home/node/.cache`, and `/tmp`: disposable tmpfs
  mounts.

There is no inbox, Docker socket, Windows drive, WSL home mount, SSH agent,
browser profile, VS Code volume, or WSLg socket.

## OpenCode adapter

OpenCode runs side by side with Codex against the same project boundary. It is
not a second sandbox design: it reuses the identical launcher verification
(`docker create`, then full mount/tmpfs/security allowlist check before
start), the same non-root user, capability drop, no-new-privileges,
read-only rootfs, resource limits, protected-path mounts, and host reports.

Enforced OpenCode-specific boundaries:

- a separate pinned image (`opencode-ai` 1.18.21 and `opencode-linux-x64`
  1.18.21, verified against npm integrity values from `versions.lock` before
  installation);
- a separate per-project authentication volume
  (`codex-sbx-<slug>-opencode-auth-v2`, labeled for the agent and project);
- task sessions mount authentication read-only; only login/logout/auth-status
  containers mount it read-write; a root-owned wrapper copies only `auth.json`
  in and synchronizes only that file back on exit;
- every OpenCode container start prunes the volume to at most `auth.json`
  inside a network-less, capability-less helper container, failing closed;
- before a new task session, matching OpenCode containers are removed and
  unremovable containers block startup. Authentication commands remove finished
  matching containers but do not stop a running authentication container;
- writable disposable tmpfs locations (`~/.local/share/opencode`,
  `~/.config`, `~/.local/state`) absorb all other state while the root
  filesystem stays read-only;
- managed configuration baked root-owned at `/etc/opencode/opencode.json`,
  together with image environment settings, is intended to disable autoupdate,
  sharing, snapshots, MCP servers, external-directory access, project/default
  plugins, and plugin/LSP downloads, and configures denials for `git push*`,
  `git commit*`, `git remote*`, `git submodule*`, and `gh *`;
- `OPENCODE_DISABLE_PROJECT_CONFIG=1` is set on the image environment, on both
  container creation paths, and again inside the auth wrapper. The
  Docker-based OpenCode smoke test checks that a repository `opencode.json`
  sentinel does not appear in resolved configuration;
- a repository `.opencode/` extension surface is shadowed with an empty tmpfs;
- normal task sessions run `opencode --pure`.

Codex and OpenCode task and shell commands share one per-project session lock
(`control/.session-lock`), preventing those launcher commands from running
against the same working tree concurrently. Authentication commands do not
mount the working tree and do not use this lock.

### Enforced boundaries versus accepted repository-level risks

The security goal is to omit Windows files, the WSL home directory, host
credentials (including SSH keys and GitHub tokens), other projects, and the
Docker daemon from the verified mount list. Project data in WSL is disposable;
GitHub is the durable source of truth. Deletion or corruption of the mounted
repository is an accepted risk. The kit does not prevent use of credentials or
writable remote URLs already stored inside the selected repository.

Repository text content is explicitly not treated as an enforceable boundary.
The pinned OpenCode release may still discover some nested `AGENTS.md`,
`CLAUDE.md`, or `CONTEXT.md` files and treat them as guidance. This kit
accepts that because repositories are personal and reviewed. It does not
modify, chmod, hide, delete, or continuously scan instruction files, and it
makes no claim that repository text cannot influence the model.

There is no mechanism intended to prevent repository instruction files from
influencing the agent. Isolation relies on the Docker boundary and managed
configuration.

## Offline runner mounts

- `/source`: current repository, read-only;
- `/agent/inbox`: selected private fixtures, read-only;
- `/agent/outbox`: review output, writable;
- `/workspace`: fresh tmpfs populated from `/source` on every invocation;
- `/home/node/.cache` and `/tmp`: disposable tmpfs mounts.

The container uses Docker network mode `none` and contains no Codex executable.
Projects needing additional offline dependencies require a separately reviewed
and locked custom offline image.

## Codex configuration

The image stores root-owned configuration at `/etc/codex/config.toml` and
root-owned constraints at `/etc/codex/requirements.toml`. The interactive
runtime uses `--strict-config` to fail on unknown keys. Codex 0.148 does not
support that flag on authentication or informational subcommands, so those
commands rely on the same root-owned configuration without the flag. Each
container receives a fresh tmpfs `CODEX_HOME`. Official Codex documentation
specifies that file-backed credential storage uses
`$CODEX_HOME/auth.json`; the enforced `cli_auth_credentials_store = "file"`
therefore makes `auth.json` the persistent allowlist. Login diagnostics and
other Codex state remain in disposable `CODEX_HOME`.

A root-owned wrapper copies `/auth/auth.json` into `CODEX_HOME`. Task,
shell, and exec containers mount `/auth` read-only, so refreshed credentials
are not synchronized from those sessions. Dedicated login and logout
containers mount `/auth` read-write without mounting the project, and the
wrapper synchronizes `auth.json` on exit. `auth-status` uses the same
authentication-only boundary with `/auth` read-only.

This deliberately does not persist token refreshes performed during a task.
The next task starts from the last credential written by login/logout; a new
login may be required if that stored credential is no longer accepted.

Before and after every Codex task or authentication command, the launcher runs
the root-owned pruning script in a network-disabled, read-only,
capability-less helper container. It removes every direct child except
`auth.json`, normalizes that file to mode 0600, verifies the postcondition,
and fails closed. Post-command cleanup is attempted after success, failure, and
interrupts when control returns to the launcher. A cleanup failure is printed
and makes an otherwise successful command fail; an existing command failure
keeps its original status while the cleanup error remains visible.

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
- an exact OpenCode version with npm integrity values for its package and
  Linux x64 binary, plus the local OpenCode image tag;
- the local image tags.

Do not use `latest`, floating base tags without digests, or automatic agent
updates. Upgrades are deliberate maintenance events:

1. Review the current official Codex/OpenCode configuration and CLI
   documentation.
2. Resolve the new npm version and package integrity values.
3. Resolve the new multi-platform base-image digest.
4. Change `versions.lock` in one reviewable commit.
5. Run `tests/static.sh`.
6. Rebuild all images.
7. Run `tests/smoke.sh` and `tests/smoke-opencode.sh` without invoking a
   model.
8. Authenticate a disposable project and run one tightly bounded model task
   only when a real end-to-end validation is justified.
9. Keep the previous image until the upgraded version is accepted.

## Authentication limitation

Codex must be able to use its ChatGPT credential, so a process inside the
networked runner can potentially read that project-specific credential. The
kit isolates authentication by project, omits host credentials from container
mounts and filters common secret environment variables, uses device
authorization, and provides logout and volume-destruction commands. It does
not eliminate credential risk.

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

Custom project images may be selected in `project.env`. They must retain the
labels, users, paths, boundary scripts, and entrypoints expected by the
launcher. A custom offline image should install reviewed, locked runtime
dependencies while keeping network access disabled at test time.

## Incident response

For a boundary-check failure, suspicious dependency, prompt-injection event, or
unexpected container behavior:

1. Stop and remove the task container.
2. Preserve the trusted host-side boundary report.
3. Review the repository and outbox from trusted WSL.
4. Run `bin/sandboxctl logout <slug>` (and
   `bin/sandboxctl logout-opencode <slug>`) when possible.
5. Run `bin/sandboxctl destroy-auth <slug> --yes` (and
   `bin/sandboxctl destroy-opencode-auth <slug> --yes`).
6. Discard disposable cache and task output.
7. Rebuild the pinned images if image integrity is in doubt.
8. Reauthenticate only after the cause is understood.

Never add privileged mode, `SYS_ADMIN`, an unconfined security profile, the
Docker socket, broad host mounts, or GUI/browser sockets as a workaround.
