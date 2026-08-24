register_sbx_agent \
  codex 'Codex' PROJECT_NETWORK_IMAGE CODEX_VERSION codex \
  project-auth-volume ensure_images 'run login doctor shell exec'

register_sbx_route codex run run
register_sbx_route codex login login
register_sbx_route codex doctor doctor
register_sbx_route codex shell shell
register_sbx_route codex exec exec
