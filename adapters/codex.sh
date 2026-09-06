register_sbx_agent \
  codex 'Codex' PROJECT_NETWORK_IMAGE CODEX_VERSION codex \
  codex-project-auth-volume ensure_codex_images 'run login auth-status logout doctor shell exec reset-auth'

register_sbx_route codex run cmd_run
register_sbx_route codex login cmd_login
register_sbx_route codex auth-status cmd_auth_status
register_sbx_route codex logout cmd_logout
register_sbx_route codex doctor cmd_doctor
register_sbx_route codex shell cmd_shell
register_sbx_route codex exec cmd_exec
register_sbx_route codex reset-auth cmd_destroy_auth
