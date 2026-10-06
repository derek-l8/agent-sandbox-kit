# Operator Guide

Use this guide for an installed kit in WSL. Replace `my-project` throughout
the examples with your project name, including in folder paths. Examples use
Codex; substitute `opencode` or `claude` as needed.
Keep the kit checkout and Git review outside agent containers.

## Installation and updates

For a first installation, follow the [README quick start](../README.md#quick-start),
including its requirements and shell `PATH` setup. Reinstall from the intended
kit checkout with `./install.sh`; it validates a staged runtime before replacing
the installed copy. The runtime lives at
`${XDG_DATA_HOME:-$HOME/.local/share}/agent-sandbox-kit`, with `sbx` linked from
`${XDG_BIN_HOME:-$HOME/.local/bin}`.

### Automatic checks

Before an agent `run`, the launcher checks the tracked kit Git remote and
published Codex, OpenCode, and Claude Code releases independently. Each check
runs when its last attempt is at least 24 hours old. A notice lets the selected
CLI continue; it does not install a release or change project configuration.
Failed automatic checks stay silent and are cached too. Explicit checks retry
regardless of the cache.

The checks run concurrently. Git has a 10-second request limit; each harness
has a 15-second resolution limit, adding at most 15 seconds of network waiting
to a launch. Harness discovery works even if the recorded kit checkout is
unavailable. Host release checks need `python3` and `timeout`; automatic checks
and installation also need `flock`.

Set an environment variable to `1` to disable the corresponding automatic checks:

| Variable | Checks disabled |
| --- | --- |
| `SBX_DISABLE_UPDATE_CHECK` | Kit and all harnesses |
| `SBX_DISABLE_HARNESS_UPDATE_CHECK` | All harnesses |
| `SBX_DISABLE_CODEX_UPDATE_CHECK` | Codex |
| `SBX_DISABLE_OPENCODE_UPDATE_CHECK` | OpenCode |
| `SBX_DISABLE_CLAUDE_UPDATE_CHECK` | Claude Code |

For example, `SBX_DISABLE_UPDATE_CHECK=1 sbx codex run my-project` skips
discovery for that invocation.

### Update one harness

Exit the current agent session before updating its project.

```bash
sbx codex-update my-project &&
sbx codex run my-project
```

Use `opencode-update` or `claude-update` for the other harnesses. A newer
release is proposed by exact version and integrity pins. Confirmation builds
and verifies only that harness's image, saves its host selection, and changes
only its reference in the named project. The project configuration is backed
up; repository files, resource settings, and logins are preserved. Applying
an already-selected release verifies its image and updates the project without
rebuilding.

Use `sbx codex-update --check` for an optional preview without applying an
update. Use `--version X.Y.Z` to request an exact stable release or `--yes` to skip
confirmation. Downgrades are refused. Discovery uses each vendor's npm `latest`
tag and accepts only non-prerelease versions. Claude uses npm's latest release,
which can differ from Anthropic's delayed `stable` channel.

Without a project, the command builds and saves the host selection while
existing projects retain their references. Rerun `sbx codex-update my-project`
to apply only Codex later, or use `sbx upgrade my-project` to apply all selected
harness images.

### Update the kit

Exit the current agent session before updating its project.

```bash
sbx update my-project &&
sbx codex run my-project
```

Use `sbx update --check` for an optional preview. The kit checkout must be
clean, on a branch with an upstream, and able to
fast-forward. Review or preserve local kit edits before updating. The project
repository is a separate directory and its files are not rewritten by this command.

`sbx update` prints the remote URL, exact commits, diff summary, and a review
command before confirmation. Confirming permits the fetched checkout's tests
and installer to run with your WSL user permissions. It fast-forwards source,
runs the Docker-free suite, installs the runtime, rebuilds changed image inputs,
and switches all image references in the named project. `--yes` skips confirmation.

An already-current kit still applies stale references in a named project.
If you pulled the kit manually, run `sbx update my-project` to install any
runtime or image changes and apply the selected images to your project.

### Rebuild and apply saved selections

`sbx build` rebuilds all selected images without discovering releases or
editing projects. `sbx upgrade my-project` backs up and atomically replaces
all project image references with the current selections; it does not build
or download. Use `sbx upgrade --dry-run my-project` to inspect the proposed
references first. Project upgrades hold the shared session lock while changing
configuration.

`sbx version` shows effective CLI versions, image tags, and selection-file
paths. CLI selections and their `.pre-update-*.bak` backups survive kit
reinstalls. A newer kit baseline supersedes a lower local CLI selection.
See [version policy](MAINTAINER-SECURITY.md#version-policy) for archive verification
and the host selection format.

### Failed updates

Registry or build failures preserve the previous CLI selection and project.
If a session starts during a CLI build, the new verified host selection can
be saved while the project stays unchanged. Exit that session and rerun the
same harness update. Concurrent installers and version updates are refused.

A kit update advances the source before testing it. If tests fail, the source
remains at the fetched commit for inspection while the installed runtime and
project stay unchanged. Updates that require image builds check Docker before
advancing the source or installing the runtime.

If an image build fails after installation, resolve the build error and rerun
`sbx update my-project`. It remembers unfinished builds, rebuilds the selected
images, and then applies the project references. If the builds succeeded but
an active session prevented the project upgrade, exit that session and rerun
the same update command; it applies the references without rebuilding.

If the recorded checkout is moved or deleted, existing agent commands still
use the copied runtime. Clone the kit and run `./install.sh` again to restore
the source update path.

## Project setup and daily use

Replace `<repo-url>` with the Git clone URL of your own committed repository;
keep the quotes. For OpenCode or Claude Code, replace `codex` with `opencode`
or `claude`.

```bash
sbx init my-project &&
git clone '<repo-url>' \
  "${CODEX_SANDBOX_WORKSPACES_ROOT:-$HOME/agent-workspaces}/my-project/repo" &&
sbx codex login my-project &&
sbx codex run my-project
```

For an existing project, start with `sbx codex run my-project`. Use
`sbx codex shell my-project` for a diagnostic shell or
`sbx codex exec my-project -- npm test` to run a command.
See [Claude authentication and limits](CLAUDE.md). Create a trusted baseline
commit before autonomous work. Linked Git worktrees are not supported.

The launcher checks the container, writes a report under `control/logs`, and
then starts it. All agents share a per-project lock. Networked runners receive
only the selected repository, read-only `/context`, writable persistent `/data`,
internet access, and their project login. They do not receive Windows drives, general
WSL home, SSH material, Docker socket, browser sessions, or editor sockets.

## External context and data

Run `sbx context my-project` and paste Windows **Copy as path** values, one
quoted path per line; finish with a blank line. It translates paths with
`wslpath`, copies regular files to the project's WSL `context/` directory,
and prints the container paths. You can import before cloning the repository.
For arguments, use `sbx context my-project add '/wsl/path/file.pdf'`.
Use single shell quotes around Windows paths passed as arguments; the
interactive prompt accepts Explorer's double quotes literally.

Imports keep each file's basename. A name collision asks before replacing
that copy. Multiple files are processed in order; a failed import stops the
batch, preserving earlier successful imports. Directories and symlinks are
not imported. Files are copied unchanged, without format detection or parsing.

`sbx context my-project list` prints imported files. To delete only a WSL copy,
use `sbx context my-project remove 'filename.pdf'`. Source files are untouched.
Imports/removals share the agent session lock; exit the task before changing
its context. Put generated files and ongoing state in `/data`, which persists
across disposable containers. Both directories are outside `repo/` and Git.
They are still available to the networked agent, and copying content into
the repository remains possible. Back up important data separately.

## Authentication maintenance

Check the current login with:

```bash
sbx codex auth-status my-project
```

Use `opencode` or `claude` for that harness's login. To sign out, run
`sbx codex logout my-project`. If an error calls for a credential reset,
inspect its exact agent and project before running the printed `reset-auth`
command. Reset deletes only that agent's saved project login and requires
`--yes`; log in again afterward. It leaves project files and other logins intact.

Task, shell, and exec sessions mount authentication read-only. Cleanup helpers
prune unexpected persistent auth content before and after commands and fail
closed on errors. Review and promote Git changes from the host.

## Settings and troubleshooting

`$HOME/agent-workspaces/my-project/control/project.env` contains fixed keys
parsed as data, not sourced as shell. Defaults are 6 CPUs and 8 GiB. Compatible
custom images must retain all labels, tools, and entrypoints verified by the
launcher. `control/protected-paths.txt` can make existing repository-relative
paths read-only.

For diagnostics without starting an agent, optionally run:

```bash
sbx codex doctor my-project
```

It checks Docker availability, project layout, image labels, and protected
mount paths. `run` checks the required conditions before launching too;
`doctor` is useful for troubleshooting and does not test authentication or
make a model request. Replace `codex` with your harness.
The default workspace root can be changed
with `CODEX_SANDBOX_WORKSPACES_ROOT`; use that root for the control-file path too.

Do not bypass a failed boundary check. Inspect the layout, control file, pinned
images, and host reports under `control/logs`.

| Error | Action |
|---|---|
| Source/installed versions differ | Run `./install.sh` from the intended checkout, then `sbx version`. |
| Image missing | Run `sbx build`. |
| Project uses an old image tag | Run `sbx upgrade my-project`. Do not edit `project.env` manually. |
| Image label differs | Run `sbx build`; never relabel an unverified image. |
| Authentication schema incompatible | Run the exact agent-specific `reset-auth` command printed by the error, then login. Only that agent/project login is deleted; repository and other agent login remain. |
| Docker daemon unavailable | Start Docker Desktop and its WSL integration, then retry. |
| Image build failed during a kit update | Resolve the build error, then rerun `sbx update my-project` to finish the builds and project upgrade. |
| OpenTUI executable-temp failure | Reinstall the current kit, rebuild, and run `bash tests/smoke-opencode.sh`; keep general `/tmp` non-executable. |

### Codex and the Bubblewrap warning

Launching Codex directly in WSL uses Codex's Linux sandbox and can warn when
Bubblewrap or unprivileged user namespaces are unavailable. `sbx codex run`
does not use that inner sandbox: it explicitly starts Codex in full-access mode
inside the already verified Docker container. The Docker launcher remains the
security boundary, including its mount allowlist, read-only root filesystem,
dropped capabilities, `no-new-privileges`, resource limits, and project lock.
Consequently the direct-WSL Bubblewrap warning is not expected for this path,
and Bubblewrap should not be added to the image as a duplicate security layer.

## Trusted-WSL validation

Run these from the reviewed host checkout, never from an agent container:

```bash
bash tests/static.sh &&
bash tests/smoke-codex.sh &&
bash tests/smoke-opencode.sh &&
bash tests/smoke-claude.sh &&
bash tests/smoke-toolchain.sh
```

Run the smoke tests only after the pinned images have been built. They use
Docker and disposable projects, requiring no real credentials or model requests.
