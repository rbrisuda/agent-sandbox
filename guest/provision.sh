#!/usr/bin/env bash
# Guest provisioning - runs as root INSIDE the VM (Ubuntu 24.04), uploaded by `sandbox create|provision`.
# Idempotent: safe to re-run. Layout:
#   /opt/agent-sandbox/{bin,agent-env.sh}            read-only tooling (root-owned)
#   /etc/agent-sandbox/sandbox.env                   settings incl. upstream proxy creds (root 600)
#   /etc/agent-sandbox/agent.env                     non-secret settings readable by the agent
#   /home/agent                                      the agent's world (no sudo, no host mounts)
set -euo pipefail

STAGE=/opt/agent-sandbox/stage
OPT=/opt/agent-sandbox
ETC=/etc/agent-sandbox
export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"

say() { printf '\033[34m[guest]\033[0m %s\n' "$*"; }

set -a
# shellcheck source=/dev/null
. "$STAGE/sandbox.env"
set +a

[ "$(id -u)" -eq 0 ] || { echo "provision.sh must run as root" >&2; exit 1; }

if command -v cloud-init >/dev/null 2>&1; then
  say "Waiting for cloud-init to finish"
  cloud-init status --wait >/dev/null 2>&1 || true
fi

# Replace the content between "# >>> agent-sandbox >>>" markers in a file (create if missing).
set_block() {
  local file="$1" content="$2" tmp
  tmp="$(mktemp)"
  if [ -f "$file" ]; then
    awk '/^# >>> agent-sandbox >>>/{skip=1} !skip{print} /^# <<< agent-sandbox <<</{skip=0}' "$file" > "$tmp"
  fi
  {
    cat "$tmp"
    echo "# >>> agent-sandbox >>> (managed, do not edit inside the markers)"
    printf '%s\n' "$content"
    echo "# <<< agent-sandbox <<<"
  } > "$file"
  rm -f "$tmp"
}

retry() { local n=0; until "$@"; do n=$((n + 1)); [ "$n" -ge 3 ] && return 1; sleep 5; done; }

# ----------------------------------------------------------------------------- files
say "Installing agent-sandbox tooling into $OPT"
install -d -m 755 "$OPT" "$OPT/bin"
install -d -m 755 "$ETC"
install -m 755 "$STAGE"/bin/* "$OPT/bin/"
install -m 644 "$STAGE/agent-env.sh" "$OPT/agent-env.sh"
install -m 644 "$STAGE/tmux.conf" /etc/tmux.conf
install -m 600 "$STAGE/sandbox.env" "$ETC/sandbox.env"
install -m 644 "$STAGE/allowlist.txt" "$ETC/allowlist.txt"
for b in agent-session agent-run agent-auth verify; do
  ln -sf "$OPT/bin/$b" "/usr/local/bin/$b"
done

# ----------------------------------------------------------------------------- CA certificates
# Corporate TLS-inspecting proxies: drop their root CA into config/certs/*.crt on the host.
if ls "$STAGE"/certs/*.crt >/dev/null 2>&1; then
  say "Installing extra CA certificates"
  install -d -m 755 /usr/local/share/ca-certificates/agent-sandbox
  install -m 644 "$STAGE"/certs/*.crt /usr/local/share/ca-certificates/agent-sandbox/
  update-ca-certificates >/dev/null
fi

# ----------------------------------------------------------------------------- packages
say "Installing base packages"
retry apt-get update -qq
retry apt-get install -y -qq --no-install-recommends \
  ca-certificates curl gnupg git git-lfs openssh-client openssh-server \
  nftables squid tmux zip unzip jq ripgrep python3 less vim nano \
  netcat-openbsd iproute2 dnsutils bash-completion locales file tree \
  ${EXTRA_APT_PACKAGES:-} >/dev/null
if ! dpkg -s chrony >/dev/null 2>&1; then
  apt-get install -y -qq systemd-timesyncd >/dev/null 2>&1 || true
fi
# Lima "plain" mode has no host clock sync: keep time right via NTP (root/system traffic only).
timedatectl set-ntp true >/dev/null 2>&1 || true

install -d -m 755 /etc/apt/keyrings
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

add_repo() {
  # add_repo NAME KEY_URL "deb line (use KEYRING placeholder)"
  local name="$1" key_url="$2" line="$3" keyring="/etc/apt/keyrings/$1.gpg"
  if [ ! -s "$keyring" ]; then
    curl -fsSL "$key_url" | gpg --dearmor --yes -o "$keyring"
    chmod 644 "$keyring"
  fi
  echo "${line//KEYRING/$keyring}" > "/etc/apt/sources.list.d/$name.list"
}

say "Adding apt repositories: Adoptium (Temurin JDK), NodeSource (Node.js $NODE_MAJOR), GitHub CLI"
add_repo adoptium https://packages.adoptium.net/artifactory/api/gpg/key/public \
  "deb [signed-by=KEYRING] https://packages.adoptium.net/artifactory/deb $CODENAME main"
add_repo nodesource https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  "deb [signed-by=KEYRING] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main"
add_repo githubcli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  "deb [arch=$ARCH signed-by=KEYRING] https://cli.github.com/packages stable main"
cat > /etc/apt/preferences.d/nodesource <<EOF
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 600
EOF
retry apt-get update -qq

JDK_PKGS=""
for v in $JDK_VERSIONS; do JDK_PKGS="$JDK_PKGS temurin-$v-jdk"; done
say "Installing JDKs ($JDK_VERSIONS), Node.js, gh"
# shellcheck disable=SC2086
retry apt-get install -y -qq $JDK_PKGS nodejs gh >/dev/null
update-ca-certificates >/dev/null 2>&1 || true

DEFAULT_JDK="${JDK_VERSIONS%% *}"
JAVA_HOME_DEFAULT="/usr/lib/jvm/temurin-$DEFAULT_JDK-jdk-$ARCH"
[ -d "$JAVA_HOME_DEFAULT" ] || JAVA_HOME_DEFAULT="$(ls -d /usr/lib/jvm/temurin-"$DEFAULT_JDK"* | head -1)"
for tool in java javac jar jshell keytool; do
  if [ -x "$JAVA_HOME_DEFAULT/bin/$tool" ]; then
    update-alternatives --set "$tool" "$JAVA_HOME_DEFAULT/bin/$tool" >/dev/null 2>&1 || true
  fi
done
JDK_PATHS="$(ls -d /usr/lib/jvm/temurin-* 2>/dev/null | paste -sd, -)"

# ----------------------------------------------------------------------------- Gradle + Maven
if [ ! -x "/opt/gradle/gradle-$GRADLE_VERSION/bin/gradle" ]; then
  say "Installing Gradle $GRADLE_VERSION (checksum verified)"
  tmp="$(mktemp -d)"
  url="https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip"
  curl -fsSL -o "$tmp/gradle.zip" "$url"
  echo "$(curl -fsSL "$url.sha256")  $tmp/gradle.zip" | sha256sum -c --quiet -
  install -d -m 755 /opt/gradle
  unzip -q -o "$tmp/gradle.zip" -d /opt/gradle
  rm -rf "$tmp"
fi
ln -sfn "/opt/gradle/gradle-$GRADLE_VERSION/bin/gradle" /usr/local/bin/gradle

if [ ! -x "/opt/maven/apache-maven-$MAVEN_VERSION/bin/mvn" ]; then
  say "Installing Maven $MAVEN_VERSION (checksum verified)"
  tmp="$(mktemp -d)"
  url="https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz"
  curl -fsSL -o "$tmp/maven.tgz" "$url"
  echo "$(curl -fsSL "$url.sha512" | awk '{print $1}')  $tmp/maven.tgz" | sha512sum -c --quiet -
  install -d -m 755 /opt/maven
  tar -xzf "$tmp/maven.tgz" -C /opt/maven
  rm -rf "$tmp"
fi
ln -sfn "/opt/maven/apache-maven-$MAVEN_VERSION/bin/mvn" /usr/local/bin/mvn

# ----------------------------------------------------------------------------- Copilot CLI
# Installed globally by root: the agent can use it but cannot modify it.
say "Installing GitHub Copilot CLI (${COPILOT_VERSION:-latest})"
retry npm install -g --no-fund --no-audit --loglevel=error "@github/copilot@${COPILOT_VERSION:-latest}"

# ----------------------------------------------------------------------------- the 'agent' user
if ! id agent >/dev/null 2>&1; then
  say "Creating unprivileged user 'agent'"
  useradd --create-home --shell /bin/bash --comment "AI coding agent" agent
fi
usermod -p '*' agent                     # no password at all (key-only SSH, cannot 'su')
for g in sudo admin adm lxd docker wheel; do gpasswd -d agent "$g" >/dev/null 2>&1 || true; done
rm -f /etc/sudoers.d/agent
# Other users' home directories (e.g. Lima's admin user) are not the agent's business.
for h in /home/*; do
  [ "$h" = /home/agent ] || chmod 700 "$h" 2>/dev/null || true
done

AH=/home/agent
install -d -m 700 -o agent -g agent "$AH/.ssh" "$AH/.agent-sandbox"
install -d -m 755 -o agent -g agent "$AH/work" "$AH/.local" "$AH/.local/bin" "$AH/.gradle" "$AH/.m2" "$AH/.copilot"
# Host access key: interactive shells + local port forwarding (JetBrains Gateway); nothing else.
echo "restrict,pty,port-forwarding $(cat "$STAGE/host_access_key.pub")" > "$AH/.ssh/authorized_keys"
chown agent:agent "$AH/.ssh/authorized_keys"; chmod 600 "$AH/.ssh/authorized_keys"

# Optional files from config/home on the host (e.g. .m2/settings.xml for a corporate Nexus).
if [ -n "$(ls -A "$STAGE/home" 2>/dev/null)" ]; then
  say "Copying config/home overlay into /home/agent"
  cp -R "$STAGE/home/." "$AH/"
  chown -R agent:agent "$AH"
fi

as_agent() { sudo -u agent -H bash -c "$1"; }

REPO_DIR="${REPO_URL%.git}"; REPO_DIR="${REPO_DIR##*/}"

cat > "$ETC/agent.env" <<EOF
# Non-secret sandbox settings for the agent user (generated by provision.sh).
SANDBOX_NAME=$(printf '%q' "$NAME")
GIT_HOST=$(printf '%q' "$GIT_HOST")
GH_HOST=$(printf '%q' "$GH_HOST")
COPILOT_HOST=$(printf '%q' "$COPILOT_HOST")
REPO_URL=$(printf '%q' "$REPO_URL")
REPO_DIR=$(printf '%q' "$REPO_DIR")
AGENT_CMD=$(printf '%q' "$AGENT_CMD")
AGENT_PROMPT_ARG=$(printf '%q' "${AGENT_PROMPT_ARG-}")
GRADLE_VERSION=$(printf '%q' "$GRADLE_VERSION")
JAVA_HOME_DEFAULT=$(printf '%q' "$JAVA_HOME_DEFAULT")
EOF
chmod 644 "$ETC/agent.env"

# Shell environment: proxy, JAVA_HOME, GH_HOST... for login, interactive and ssh-command shells.
cat > /etc/profile.d/zz-agent-sandbox.sh <<'EOF'
if [ "$(id -un)" = agent ] && [ -r /opt/agent-sandbox/agent-env.sh ]; then . /opt/agent-sandbox/agent-env.sh; fi
EOF
if ! grep -q 'agent-sandbox/agent-env.sh' /etc/bash.bashrc; then
  { echo '[ "$(id -un)" = agent ] && [ -r /opt/agent-sandbox/agent-env.sh ] && . /opt/agent-sandbox/agent-env.sh # agent-sandbox'
    cat /etc/bash.bashrc; } > /etc/bash.bashrc.new && mv /etc/bash.bashrc.new /etc/bash.bashrc
fi

say "Configuring git, SSH, Gradle, Maven and npm for the agent"
as_agent "git config --global user.name $(printf '%q' "$GIT_USER_NAME")"
as_agent "git config --global user.email $(printf '%q' "$GIT_USER_EMAIL")"
as_agent "git config --global init.defaultBranch main"
as_agent "git config --global push.autoSetupRemote true"
as_agent "git config --global fetch.prune true"

# Git deploy key: generated INSIDE the VM; the private key never leaves it.
if [ ! -f "$AH/.ssh/id_ed25519_git" ]; then
  as_agent "ssh-keygen -q -t ed25519 -N '' -C 'agent-sandbox-$NAME' -f ~/.ssh/id_ed25519_git"
fi
set_block "$AH/.ssh/config" "Host $GIT_HOST
  User git
  IdentityFile ~/.ssh/id_ed25519_git
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  # All agent traffic must go through the egress proxy (it permits port 22 only to $GIT_HOST).
  ProxyCommand /opt/agent-sandbox/bin/proxy-connect %h %p"
if [ "$GIT_HOST" = github.com ] && ! grep -q '^github.com ssh-ed25519' "$AH/.ssh/known_hosts" 2>/dev/null; then
  # Published at https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> "$AH/.ssh/known_hosts"
fi
chown agent:agent "$AH/.ssh/config" "$AH/.ssh/known_hosts" 2>/dev/null || true
chmod 600 "$AH/.ssh/config"

set_block "$AH/.gradle/gradle.properties" "systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=3128
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=3128
systemProp.http.nonProxyHosts=localhost|127.*|[::1]
systemProp.https.nonProxyHosts=localhost|127.*|[::1]
org.gradle.java.installations.paths=$JDK_PATHS
org.gradle.java.installations.auto-detect=true"
chown agent:agent "$AH/.gradle/gradle.properties"

if [ ! -f "$AH/.m2/settings.xml" ]; then
  cat > "$AH/.m2/settings.xml" <<'EOF'
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0">
  <!-- Generated by agent-sandbox: all traffic goes through the in-VM egress proxy. -->
  <proxies>
    <proxy><id>sandbox-http</id><active>true</active><protocol>http</protocol>
      <host>127.0.0.1</host><port>3128</port><nonProxyHosts>localhost|127.*</nonProxyHosts></proxy>
    <proxy><id>sandbox-https</id><active>true</active><protocol>https</protocol>
      <host>127.0.0.1</host><port>3128</port><nonProxyHosts>localhost|127.*</nonProxyHosts></proxy>
  </proxies>
</settings>
EOF
  chown agent:agent "$AH/.m2/settings.xml"
elif ! grep -q '<proxies>' "$AH/.m2/settings.xml"; then
  echo "WARNING: /home/agent/.m2/settings.xml has no <proxies> section; Maven downloads will be blocked. See docs/08-java-kotlin.md" >&2
fi

as_agent "npm config set prefix ~/.local >/dev/null; npm config set fund false; npm config set update-notifier false"

if [ ! -f "$AH/.copilot/copilot-instructions.md" ]; then
  install -m 644 -o agent -g agent "$STAGE/copilot-instructions.md" "$AH/.copilot/copilot-instructions.md"
fi
chown agent:agent "$AH/.copilot" "$AH/.local" "$AH/.local/bin" "$AH/work"

# ----------------------------------------------------------------------------- sshd hardening
say "Hardening sshd"
cat > /etc/ssh/sshd_config.d/10-agent-sandbox.conf <<'EOF'
# agent-sandbox: key-only logins, no agent/X11/tunnel forwarding.
# AllowTcpForwarding stays "local" so JetBrains Gateway can reach its backend inside the VM.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
AllowAgentForwarding no
AllowTcpForwarding local
AllowStreamLocalForwarding no
X11Forwarding no
PermitTunnel no
GatewayPorts no
PermitUserEnvironment no
EOF
if ! sshd -t 2>/dev/null; then
  echo "WARNING: sshd rejected the hardening drop-in; removing it" >&2
  rm -f /etc/ssh/sshd_config.d/10-agent-sandbox.conf
fi
systemctl try-reload-or-restart ssh.service >/dev/null 2>&1 || true

# ----------------------------------------------------------------------------- IPv6 + DNS
# The egress policy is IPv4; disable IPv6 except on loopback.
cat > /etc/sysctl.d/90-agent-sandbox.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 0
EOF
sysctl -q -p /etc/sysctl.d/90-agent-sandbox.conf >/dev/null 2>&1 || true

# With AGENT_DNS=block the agent must not resolve names itself (DNS can carry data out).
# systemd-resolved answers any local user over D-Bus, bypassing a port-53 firewall rule, so
# it is replaced by a static resolv.conf that only root/system services (squid) use.
if [ "${AGENT_DNS:-block}" = block ] && systemctl is-active -q systemd-resolved 2>/dev/null; then
  say "Replacing systemd-resolved with a static resolver config"
  servers="$(resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '^127\.' | awk '!s[$0]++' | head -3 || true)"
  [ -n "$servers" ] || servers="192.168.5.3"   # Lima's built-in DNS
  if [ -n "$servers" ]; then
    systemctl disable --now systemd-resolved >/dev/null 2>&1 || true
    rm -f /etc/resolv.conf
    { for s in $servers; do echo "nameserver $s"; done; echo "options edns0 timeout:2"; } > /etc/resolv.conf
  else
    echo "WARNING: could not determine upstream DNS servers; keeping systemd-resolved" >&2
  fi
fi

# ----------------------------------------------------------------------------- egress policy
say "Applying egress policy (mode: $NETWORK_MODE)"
install -m 644 "$STAGE/agent-sandbox-network.service" /etc/systemd/system/agent-sandbox-network.service
systemctl daemon-reload
systemctl enable agent-sandbox-network.service >/dev/null 2>&1
systemctl enable squid.service >/dev/null 2>&1 || true
"$OPT/bin/apply-network"

date -u +%FT%TZ > "$ETC/provisioned"
rm -rf "$STAGE"
say "Provisioning complete"
