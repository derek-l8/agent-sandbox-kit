register_sbx_agent \
  opencode 'OpenCode' PROJECT_OPENCODE_IMAGE OPENCODE_VERSION opencode \
  separate-project-auth-volume ensure_opencode_image 'run login auth-status logout doctor shell exec reset-auth'

register_sbx_route opencode run run-opencode
register_sbx_route opencode login login-opencode
register_sbx_route opencode auth-status auth-status-opencode
register_sbx_route opencode logout logout-opencode
register_sbx_route opencode doctor doctor-opencode
register_sbx_route opencode shell shell-opencode
register_sbx_route opencode exec exec-opencode
register_sbx_route opencode reset-auth destroy-opencode-auth
