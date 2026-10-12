# shellcheck shell=bash
# Environment for the 'agent' user inside the sandbox. Sourced by login shells, interactive
# shells, SSH commands and every agent-sandbox helper script.

if [ -r /etc/agent-sandbox/agent.env ]; then
  # shellcheck source=/dev/null
  . /etc/agent-sandbox/agent.env
fi

# All outbound traffic of the agent goes through the in-VM allowlist proxy (squid).
# In "allowlist" mode the firewall drops every direct connection, so tools that ignore
# these variables fail fast instead of leaking.
export http_proxy=http://127.0.0.1:3128
export https_proxy=http://127.0.0.1:3128
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export no_proxy=localhost,127.0.0.1,::1
export NO_PROXY="$no_proxy"

# Node.js >= 24 honours the proxy variables for http/https/fetch with this flag.
export NODE_USE_ENV_PROXY=1
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

export SANDBOX=1
export AGENT_SANDBOX_NAME="${SANDBOX_NAME:-}"
[ -n "${GH_HOST:-}" ] && export GH_HOST
# gh may target a GitHub Enterprise Server while Copilot uses github.com (or a ghe.com tenant).
[ -n "${COPILOT_HOST:-}" ] && export COPILOT_GH_HOST="$COPILOT_HOST"
export COPILOT_AUTO_UPDATE=false

if [ -n "${JAVA_HOME_DEFAULT:-}" ] && [ -d "$JAVA_HOME_DEFAULT" ]; then
  export JAVA_HOME="$JAVA_HOME_DEFAULT"
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:/opt/agent-sandbox/bin:$PATH" ;;
esac

# Make it obvious where you are.
if [ -n "${PS1:-}" ]; then
  PS1='\[\e[1;35m\][sandbox:${AGENT_SANDBOX_NAME}]\[\e[0m\] \u@\h:\w\$ '
fi
