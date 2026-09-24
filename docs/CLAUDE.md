# Claude Code adapter

The adapter pins Claude Code 2.1.280 and its Linux x64 npm binary. It uses the
same Docker boundary as Codex and OpenCode: non-root, read-only root filesystem,
no capabilities, no-new-privileges, no published ports or host sockets, and the
existing CPU, memory, and process limits. Network access is enabled.

## Install or update

Run these commands in WSL from the reviewed kit checkout:

```bash
./install.sh
sbx build
sbx upgrade my-project
sbx claude doctor my-project
sbx claude login my-project
sbx claude auth-status my-project
sbx claude run my-project
```

Replace `my-project` with the existing project slug. `upgrade` preserves its
repository, context, data, resource settings, and other agents' credentials.
For a new project, use `sbx init` and clone a repository into its `repo` folder.

Login runs without mounting the repository, `/context`, or `/data`. Follow the
URL and code prompts in Claude's terminal using your Windows browser. No ports
are published for a browser callback. Use a Claude subscription account; API
keys, Console billing, third-party providers, and host credential import are
outside this adapter's tested scope.

## Storage and commands

`run`, `shell`, and `exec` mount `/workspace` writable, its `.git` read-only,
`/context` read-only, and `/data` writable. They share the kit's per-project
session lock with the other agents. Claude authentication commands also take
that lock to avoid concurrent credential changes.

The separate `codex-sbx-<slug>-claude-auth-v2` Docker volume persists only
`.credentials.json`. It has agent/project/schema labels and is pruned before
and after use. Unexpected files are removed and cause failure; malformed or
non-regular credential files are refused. Its contents are sensitive.

Task containers mount this volume read-only and copy credentials into a fresh
tmpfs at `/home/node/.claude`. Settings, transcripts, trust decisions, account
display metadata, caches, and plugin state are discarded. Account email and
organization fields can therefore be absent from `auth-status`.

Task-time token refresh is **not saved** to the persistent volume. If a later
session reports an expired or invalid login, run `sbx claude login my-project`
again. Real subscription login and refresh across multiple sessions require a
manual acceptance test; synthetic credential recognition does not prove them.

```bash
sbx claude shell my-project
sbx claude exec my-project -- python3 --version
sbx claude auth-status my-project
sbx claude logout my-project
sbx claude reset-auth my-project --yes
```

`auth-status` uses a read-only credential mount and returns nonzero when logged
out. `logout` removes the saved login. `reset-auth` deletes only this project's
Claude volume and is for deliberate credential reset.

## Configuration policy

Root-owned `/etc/claude-code/managed-settings.json` disables hooks and command
plugin sources, blocks plugin marketplaces and sideload flags, and restricts
user-added MCP servers to an empty allowlist. Normal `run` also excludes user,
project, and local settings, selects strict MCP configuration, and disables
slash-command skills. The kit appends its workspace guidance to Claude's
system prompt. Repository `CLAUDE.md` remains instruction text, not a security
boundary. Read repository `AGENTS.md` when applicable.

Claude runs with `--dangerously-skip-permissions`: Docker enforces the filesystem
boundary, not Claude permission prompts. This does not prevent network
exfiltration or protect files writable inside `/workspace` and `/data`. The
agent can read its own credential. Use repositories and context you trust to
the selected account. No host authentication, MCP servers, or plugins are
imported. Automatic updates are disabled; update the reviewed pins instead.

## Validation

```bash
bash tests/static.sh
bash tests/smoke-claude.sh
```

The smoke test uses a disposable project and auth volume, checks actual mounts,
CLI startup, missing-login behavior, logout, data persistence, and suppression
of repository hook/MCP commands. It uses synthetic credential placeholders to
check file recognition and task-copy isolation. It does not supply real credentials or complete a
model request. The Codex and OpenCode smoke tests cover regressions separately.

For manual acceptance, log in, confirm `auth-status`, and ask Claude to read a
file from `/context`, write a small result to `/data`, and run the repository's
tests. Exit and start another session to check login reuse. Review the Git diff
outside Docker. Finally test logout/status and sign back in if desired.

Upstream references used for this pin:

- [Authentication and credential storage](https://code.claude.com/docs/en/authentication)
- [CLI flags](https://code.claude.com/docs/en/cli-reference)
- [Managed configuration](https://code.claude.com/docs/en/settings-reference)
- [Environment variables](https://code.claude.com/docs/en/env-vars)

Package and binary integrity values were obtained from the official npm
registry metadata on 2026-09-22. The Docker build checks both exact-version
values before installation; `doctor` verifies the image's recorded pins.
