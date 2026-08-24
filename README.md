# Agent Sandbox Kit

Agent Sandbox Kit runs Codex and OpenCode in disposable Docker containers from
WSL. Each agent receives one selected Git working tree without mounts for the
rest of the WSL home, Windows files, host credentials, or the Docker socket.

The durable repository and installation name is `agent-sandbox-kit`. This is
an experimental personal project for repositories you own and review, not a
general sandbox for untrusted repositories.

## Quick start

```bash
git clone <REPOSITORY-URL> agent-sandbox-kit
cd agent-sandbox-kit
./install.sh
sbx build
sbx init my-project
git clone https://github.com/OWNER/REPOSITORY.git \
  "$HOME/agent-workspaces/my-project/repo"
sbx codex doctor my-project
sbx codex login my-project
sbx codex run my-project
```

The installer links `sbx` into `~/.local/bin` without root access. If that
directory is not on `PATH`, it prints the exact shell setup line to add.

OpenCode uses the same shape:

```bash
sbx opencode doctor my-project
sbx opencode login my-project
sbx opencode run my-project
```

Create a trusted baseline commit before an agent session. Review, commit, and
push from WSL, outside the container.

## Everyday commands

| Purpose | Codex | OpenCode |
| --- | --- | --- |
| Start agent | `sbx codex run <project>` | `sbx opencode run <project>` |
| Log in | `sbx codex login <project>` | `sbx opencode login <project>` |
| Validate | `sbx codex doctor <project>` | `sbx opencode doctor <project>` |
| Diagnostic shell | `sbx codex shell <project>` | `sbx opencode shell <project>` |
| Run a command | `sbx codex exec <project> -- <command>` | `sbx opencode exec <project> -- <command>` |

Shared setup commands are `sbx init <project>` and `sbx build`.

The CLI uses an explicit allowlisted adapter registry. Agent-specific image,
executable, version, authentication, configuration-validation, and command
routing metadata is kept under `adapters/`. Docker isolation, verified mounts,
resource limits, project locking, cleanup, and protected paths remain in the
common launcher and cannot be configured by an adapter. See
[Adding an Agent](docs/ADDING-AN-AGENT.md).

## Trust model

The trusted WSL launcher creates containers directly and checks their final
configuration before startup. The repository is writable while `.git` is
read-only. Agents have separate pinned images and authentication volumes, and
a shared project lock prevents concurrent sessions on one tree. Authentication
is mounted read-only during task, shell, and exec sessions.

The kit does not guarantee protection from Docker or kernel vulnerabilities,
safe handling of arbitrary malicious repositories, protection of an active
agent credential from repository code, or preservation of the writable tree.
See the [operator guide](docs/OPERATOR-GUIDE.md) and
[security reference](docs/MAINTAINER-SECURITY.md).

## Advanced and compatibility commands

`bin/sbx` is a small argument-preserving wrapper around `bin/sandboxctl`; it
contains no container or security logic. The original launcher remains
supported with every existing command and behavior:

```bash
bin/sandboxctl --help
bin/sandboxctl run <project>
bin/sandboxctl run-opencode <project>
bin/sandboxctl offline <project> -- <command>
bin/sandboxctl package <project>
bin/sandboxctl auth-status <project>
bin/sandboxctl auth-status-opencode <project>
```

The workspace root defaults to `$HOME/agent-workspaces`; set
`CODEX_SANDBOX_WORKSPACES_ROOT` for another WSL location. Projects require a
normal `.git` directory, so linked Git worktrees are not supported.

## Tests

Complete Docker-free, authentication-free, and model-free suite:

```bash
bash tests/static.sh
```

Docker-based, model-free smoke checks:

```bash
bash tests/smoke.sh
bash tests/smoke-opencode.sh
```

## License

MIT. See [LICENSE](LICENSE).
