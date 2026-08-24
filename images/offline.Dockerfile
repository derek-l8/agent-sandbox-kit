ARG BASE_IMAGE=invalid.local/codex-sandbox-base-must-be-supplied:0
FROM ${BASE_IMAGE}

ARG KIT_VERSION
ARG BASE_IMAGE

USER root

COPY container/check-common.sh /usr/local/lib/codex-sandbox/check-common.sh
COPY container/check-offline.sh /usr/local/bin/check-offline-boundaries
COPY container/start-offline-session.sh /usr/local/bin/start-offline-session

RUN chmod 0555 /usr/local/lib/codex-sandbox/check-common.sh \
        /usr/local/bin/check-offline-boundaries \
        /usr/local/bin/start-offline-session \
    && printf 'offline-private-test\n' > /etc/agent-mode \
    && chmod 0444 /etc/agent-mode \
    && mkdir -p /workspace /source /agent/inbox /agent/outbox /home/node/.cache \
    && chown -R node:node /workspace /agent /home/node/.cache \
    && rm -f /etc/sudoers.d/node \
    && ! command -v codex

LABEL org.opencontainers.image.title="Codex Sandbox Offline Runner" \
      io.codex-sandbox.kit.version="${KIT_VERSION}" \
      io.codex-sandbox.base.image="${BASE_IMAGE}" \
      io.codex-sandbox.mode="offline-private-test"

ENV AGENT_MODE=offline-private-test \
    HISTFILE=/dev/null \
    XDG_CACHE_HOME=/home/node/.cache \
    NPM_CONFIG_CACHE=/home/node/.cache/npm \
    PIP_CACHE_DIR=/home/node/.cache/pip

USER node
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/start-offline-session"]
CMD ["bash"]
