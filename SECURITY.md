# Security policy

## Reporting a vulnerability

Use GitHub's
[private vulnerability reporting](https://github.com/derek-l8/agent-sandbox-kit/security/advisories/new)
for a suspected vulnerability. Do not include credentials or private repository
content in a public issue.

Include the affected command, relevant version or commit, expected boundary,
observed behavior, and a minimal reproduction when possible. There is no formal
response-time or bounty commitment.

## Supported version

Security fixes target the current `main` branch.

## Scope

The kit is an experimental personal project. Its Docker boundary limits mounts,
privileges, resources, and credential persistence, but it does not guarantee:

- protection from Docker or kernel vulnerabilities;
- safe execution of arbitrary malicious repositories;
- secrecy of credentials or files available to the running agent; or
- preservation of the writable repository or `/data` contents.

Review the [trust model](README.md#trust-model) and
[security reference](docs/MAINTAINER-SECURITY.md) before use.
