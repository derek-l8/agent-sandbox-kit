# Adding an Agent

Agent Sandbox Kit uses an explicit allowlist. Merely adding an adapter file does
not enable an agent. A new agent such as Claude Code requires all of the work
below; Claude Code is not installed or implemented by this repository.

## Files and integration points

1. Add `adapters/<agent>.sh` with `register_sbx_agent` metadata and routes for
   `run`, `login`, `doctor`, `shell`, and `exec`.
2. Add one explicit `source` line in `adapters/registry.sh`. Do not discover or
   execute adapter files dynamically.
3. Add pinned package, binary, base-image, and integrity values to
   `versions.lock`; update its fixed-key parser in `bin/sandboxctl`.
4. Add a dedicated Dockerfile and root-owned entrypoint/credential helpers.
   Keep managed configuration in `config/` and bake it into the image.
5. Add narrowly named project configuration keys only when required. Parse them
   with an allowlist; never source project files as shell.
6. Add the agent command handlers and container creator to `bin/sandboxctl`.
   Reuse the common resource arguments, mount verifier, lock, cleanup lifecycle,
   protected-path loader, and container runner. Do not put Docker flags in
   adapter metadata.
7. Update the README, operator guide, and maintainer security reference.

## Required security review

Document the executable's startup and update behavior, all writable paths,
environment variables, subprocess and shell behavior, repository-local
instruction/config/plugin discovery, telemetry and sharing defaults, network
listeners, MCP or extension loading, and Git/GitHub capabilities. Establish
managed settings that disable automatic updates, sharing, external extensions,
project configuration, and unsafe promotion operations where the product
supports this.

Authentication needs a separate investigation: identify every credential file,
token refresh behavior, login/logout/status commands, file permissions, and
whether task-time refresh must persist. Use a dedicated per-project volume,
mount it read-only for run/shell/exec, mount no workspace during authentication,
and implement a fail-closed before/after prune with an exact file allowlist.
Never assume another agent's `auth.json` format or lifecycle applies.

An adapter may select only reviewed agent metadata and existing handler routes.
It must not control mounts, network mode, capabilities, devices, ports,
privilege, root filesystem mutability, resource limits, protected paths,
verification, locking, or cleanup. Any needed boundary change belongs in common
code and requires a security review for every registered agent.

## Tests and pins

Extend `tests/adapter-conformance.sh` and `tests/sbx-cli.sh`, then add Docker-free
stub tests for every handler. Cover exact forwarding after `--`, image and
entrypoint selection, allowed mounts and tmpfs, read-only task authentication,
writable auth-only login, no workspace during login, lock sharing, stale
cleanup, prune on success/failure/interruption, managed configuration, invalid
configuration, and backward-compatible `sandboxctl` commands.

Pin the base image by digest and the agent/package/binary by exact version and
published integrity hash. The build must independently verify each integrity
value and bake labels that `doctor` checks. Record how the upstream artifact
and hashes were obtained and review upstream release notes before changing a
pin.

Run the complete Docker-free suite:

```bash
bash tests/static.sh
```

## Docker checks before registration

Only after Docker-free review passes, build and inspect the image. Confirm the
effective non-root user, root-owned entrypoints/configuration, executable and
version, disabled updater/project plugins, expected writable paths, and no
embedded credentials. Run model-free smoke tests that inspect the final
container for a read-only root, all capabilities dropped, no-new-privileges,
resource limits, no devices or published ports, exact network mode, exact mount
and tmpfs allowlists, project-only workspace access, read-only `.git`, and
read-only task authentication. Exercise login/status/logout with a disposable
test identity, then verify pruning and volume destruction separately.

Finally, have the security changes reviewed before adding the adapter's source
line to the allowlist. Registration is the last step, not the first.
