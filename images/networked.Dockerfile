ARG BASE_IMAGE=invalid.local/codex-sandbox-base-must-be-supplied:0
FROM ${BASE_IMAGE}

ARG KIT_VERSION
ARG CODEX_VERSION
ARG CODEX_PACKAGE_INTEGRITY
ARG CODEX_LINUX_X64_INTEGRITY
ARG BASE_IMAGE

USER root

RUN test "$(npm view "@openai/codex@${CODEX_VERSION}" dist.integrity)" = "${CODEX_PACKAGE_INTEGRITY}" \
    && test "$(npm view "@openai/codex@${CODEX_VERSION}-linux-x64" dist.integrity)" = "${CODEX_LINUX_X64_INTEGRITY}" \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force \
    && test "$(codex --version | awk '{print $2}')" = "${CODEX_VERSION}"

COPY config/config.toml /etc/codex/config.toml
COPY config/requirements.toml /etc/codex/requirements.toml
COPY container/check-common.sh /usr/local/lib/codex-sandbox/check-common.sh
COPY container/check-networked.sh /usr/local/bin/check-networked-boundaries
COPY container/check-login.sh /usr/local/bin/check-login-boundaries
COPY container/prune-auth-volume.sh /usr/local/lib/codex-sandbox/prune-auth-volume
COPY container/run-with-project-auth.sh /usr/local/bin/run-with-project-auth
COPY container/start-auth-session.sh /usr/local/bin/start-auth-session
COPY container/start-networked-session.sh /usr/local/bin/start-networked-session

RUN chmod 0444 /etc/codex/config.toml /etc/codex/requirements.toml \
    && chmod 0555 /usr/local/lib/codex-sandbox/check-common.sh \
        /usr/local/lib/codex-sandbox/prune-auth-volume \
        /usr/local/bin/check-networked-boundaries \
        /usr/local/bin/check-login-boundaries \
        /usr/local/bin/run-with-project-auth \
        /usr/local/bin/start-auth-session \
        /usr/local/bin/start-networked-session \
    && printf 'networked-public\n' > /etc/agent-mode \
    && chmod 0444 /etc/agent-mode \
    && mkdir -p /auth /home/node/.codex /home/node/.cache /workspace \
    && chown -R node:node /auth /home/node/.codex /home/node/.cache /workspace \
    && rm -f /etc/sudoers.d/node

LABEL org.opencontainers.image.title="Codex Sandbox Networked Runner" \
      io.codex-sandbox.kit.version="${KIT_VERSION}" \
      io.codex-sandbox.codex.version="${CODEX_VERSION}" \
      io.codex-sandbox.base.image="${BASE_IMAGE}" \
      io.codex-sandbox.mode="networked-public"

ENV CODEX_HOME=/home/node/.codex \
    AGENT_MODE=networked-public \
    GIT_OPTIONAL_LOCKS=0 \
    HISTFILE=/dev/null \
    XDG_CACHE_HOME=/home/node/.cache \
    NPM_CONFIG_CACHE=/home/node/.cache/npm \
    PIP_CACHE_DIR=/home/node/.cache/pip

USER node
WORKDIR /workspace
CMD ["codex", "--strict-config", "--disable", "apps", "--disable", "remote_plugin", "--dangerously-bypass-approvals-and-sandbox"]
