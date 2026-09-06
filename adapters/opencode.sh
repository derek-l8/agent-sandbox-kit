register_sbx_agent \
  opencode 'OpenCode' PROJECT_OPENCODE_IMAGE OPENCODE_VERSION opencode \
  separate-project-auth-volume ensure_opencode_image 'run login auth-status logout doctor shell exec reset-auth'

register_sbx_route opencode run cmd_run_opencode
register_sbx_route opencode login cmd_login_opencode
register_sbx_route opencode auth-status cmd_auth_status_opencode
register_sbx_route opencode logout cmd_logout_opencode
register_sbx_route opencode doctor cmd_doctor_opencode
register_sbx_route opencode shell cmd_shell_opencode
register_sbx_route opencode exec cmd_exec_opencode
register_sbx_route opencode reset-auth cmd_destroy_opencode_auth
