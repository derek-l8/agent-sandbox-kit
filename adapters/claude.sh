register_sbx_agent \
  claude 'Claude Code' PROJECT_CLAUDE_IMAGE CLAUDE_VERSION claude \
  claude-project-auth-volume ensure_claude_images 'run login auth-status logout doctor shell exec reset-auth'

register_sbx_route claude run cmd_run_claude
register_sbx_route claude login cmd_login_claude
register_sbx_route claude auth-status cmd_auth_status_claude
register_sbx_route claude logout cmd_logout_claude
register_sbx_route claude doctor cmd_doctor_claude
register_sbx_route claude shell cmd_shell_claude
register_sbx_route claude exec cmd_exec_claude
register_sbx_route claude reset-auth cmd_destroy_auth_claude
