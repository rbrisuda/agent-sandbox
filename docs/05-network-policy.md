# 5. Network policy

## Modes

| Mode | Agent can reach | Use when |
|---|---|---|
| `allowlist` (default) | Only domains in the sandbox's allowlist, through the in-VM proxy (`127.0.0.1:3128`). Direct connections are dropped. | Normal work: you know which registries are needed. |
| `open` | Any **public** internet host (directly or through the proxy). Private, LAN, host and metadata ranges are still dropped. | Exploring, or when you cannot predict the needed domains. Switch back afterwards. |

```bash
sandbox network my-project open        # temporarily
sandbox network my-project allowlist   # back
```

In both modes the following are always blocked for the agent:

- the host,
- the LAN/VPN (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`),
- link-local and cloud metadata (`169.254/16`),
- multicast.

To reach a specific internal range, allow it with `ALLOW_CIDRS`.

## How it is enforced

```mermaid
flowchart LR
  subgraph VM
    agent["agent user<br/>(curl, gradle, mvn, npm, copilot, git)"]
    squid["squid :3128<br/>domain allowlist<br/>CONNECT :443 (+ :22 to git host)"]
    nft["nftables<br/>meta skuid agent → only loopback"]
  end
  agent -- "HTTP(S)_PROXY" --> squid --> net[(Internet)]
  agent -. "direct" .-> nft -. "drop" .-> x((✗))
```

1. **nftables, inside the VM:**
   - Outgoing packets from the `agent` uid that do not go to loopback are dropped in
     `allowlist` mode.
   - In `open` mode only private ranges are dropped.
   - This also stops tools that ignore proxy settings, and anything that tries raw IPs.
2. **squid, inside the VM:**
   - Only accepts connections from localhost.
   - Allows `CONNECT` to port 443 for allowlisted domains, and to port 22 **only** for the
     configured `GIT_HOST` (git over SSH, via `ProxyCommand`).
   - Denies private destinations, even if a public name resolves to a private IP (DNS
     rebinding).
3. **DNS:** with `AGENT_DNS=block` (default) the agent cannot query DNS at all, and squid
   resolves the names.
   - `systemd-resolved` is replaced by a static `/etc/resolv.conf`, because resolved answers
     any local user over D-Bus.

Every agent process gets the proxy settings automatically:

| Tool | How it is configured |
|---|---|
| curl, git (https), gh, npm, pip | `HTTP(S)_PROXY` / `http(s)_proxy` / `NO_PROXY` |
| Node.js, Copilot CLI | `NODE_USE_ENV_PROXY=1` (Node ≥ 24) |
| Gradle (and the wrapper download) | `~/.gradle/gradle.properties` → `systemProp.http(s).proxyHost/Port` |
| Maven | `~/.m2/settings.xml` → `<proxies>` |
| git over SSH | `~/.ssh/config` → `ProxyCommand /opt/agent-sandbox/bin/proxy-connect %h %p` |
| Plain JVM programs | not automatic. Pass `-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=3128` (or `-Djava.net.useSystemProxies=true`). |

## Managing the allowlist

The allowlist is built at `sandbox create` time from:

- the presets in `config/allowlist/*.txt` (`ALLOWLISTS="core java"` by default; also `node`,
  `python`, `jetbrains`),
- plus `config/allowlist.local.txt` (git-ignored, your personal additions),
- plus `EXTRA_ALLOW_DOMAINS`,
- plus `GIT_HOST`, `GH_HOST` and `COPILOT_HOST`, which are always added.

Each sandbox keeps its own copy at `~/.agent-sandbox/sandboxes/<name>/allowlist.txt`.

```bash
sandbox blocked my-project                 # what was denied?  (count + domain)
sandbox blocked my-project -f              # live
sandbox allow my-project .jitpack.io       # leading dot = include subdomains (also accepts *.jitpack.io)
$EDITOR ~/.agent-sandbox/sandboxes/my-project/allowlist.txt && sandbox network my-project reload
```

The agent's instructions (`~/.copilot/copilot-instructions.md`) tell it to *report* blocked
domains instead of working around them. You decide what to allow.

**Allowlist hygiene:**

- Prefer specific hosts over wide wildcards.
- Avoid general-purpose hosts that accept uploads, such as paste sites, `*.s3.amazonaws.com`,
  `*.blob.core.windows.net` and URL shorteners. Every allowed domain is a possible exfiltration
  path.

## Corporate environments

| Situation | Setting |
|---|---|
| Internal Nexus/Artifactory/GHES on a private IP | `ALLOW_CIDRS="10.20.30.0/24"` and its hostname in `EXTRA_ALLOW_DOMAINS` (or in `GIT_HOST`/`GH_HOST`) |
| Explicit corporate proxy | `UPSTREAM_PROXY="http://user:pass@proxy.corp:8080"`. squid chains to it. If its IP is private, also add it to `ALLOW_CIDRS`. The credentials stay root-only in the VM. |
| TLS inspection (custom root CA) | Put `corp-root.crt` (PEM) into `config/certs/`, then `sandbox provision <name>` |
| Nexus mirror for Maven | `config/home/.m2/settings.xml` with `<mirrors>` **and** the `<proxies>` block (see [docs/08](08-development-tooling.md)) |

## Limitations

- **The policy is IPv4 only.** IPv6 is disabled in the VM (sysctl).
- **Root traffic is not filtered inside the VM.** apt, provisioning and NTP need it, and the
  agent has no root. Run `sandbox shell --admin` with care.
- **Allowed domains can carry data out.** An allowed `github.com` can also receive
  pushes/gists/issues from the agent. Keep tokens scoped (see [docs/06](06-credentials.md)).
