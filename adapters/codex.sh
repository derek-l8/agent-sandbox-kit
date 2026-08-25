register_sbx_agent \
  codex 'Codex' PROJECT_NETWORK_IMAGE CODEX_VERSION codex \
  codex-project-auth-volume ensure_codex_images 'run login auth-status logout doctor shell exec reset-auth'

register_sbx_route codex run run
register_sbx_route codex login login
register_sbx_route codex auth-status auth-status
register_sbx_route codex logout logout
register_sbx_route codex doctor doctor
register_sbx_route codex shell shell
register_sbx_route codex exec exec
register_sbx_route codex reset-auth destroy-auth
