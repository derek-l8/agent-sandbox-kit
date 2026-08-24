register_sbx_agent \
  opencode 'OpenCode' PROJECT_OPENCODE_IMAGE OPENCODE_VERSION opencode \
  separate-project-auth-volume ensure_opencode_image 'run login doctor shell exec'

register_sbx_route opencode run run-opencode
register_sbx_route opencode login login-opencode
register_sbx_route opencode doctor doctor-opencode
register_sbx_route opencode shell shell-opencode
register_sbx_route opencode exec exec-opencode
