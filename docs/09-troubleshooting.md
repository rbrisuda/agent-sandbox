# 9. Troubleshooting

Start with:

```bash
sandbox status <name>
sandbox verify <name>        # PASS/FAIL list
sandbox blocked <name>       # proxy denials + firewall drop counters
```

## Creation / boot

| Symptom | Fix |
|---|---|
| `limactl create` fails to download the image | Check internet/VPN on the host. Image URLs are in `lib/vm.sh`. |
| `macOS 13.5+ is required` | Update macOS (Virtualization.framework needs 13.5+). |
| Linux: `/dev/kvm not found` / permission denied | Enable VT-x/AMD-V in BIOS/UEFI, `sudo modprobe kvm_intel` (or `kvm_amd`), `sudo usermod -aG kvm $USER`, then log out/in. See [docs/03](03-setup.md). |
| Provisioning stopped half-way | Fix the cause (often a temporary download error), then run `sandbox provision <name>`. It is idempotent. |
| `Permission denied (publickey)` on `sandbox shell` | Provisioning did not finish (authorized_keys for `agent` missing). Run `sandbox provision <name>`. |
| Host key changed warning | The VM was recreated under the same name outside the CLI. Delete `~/.agent-sandbox/sandboxes/<name>/known_hosts`. |

## Network

| Symptom | Fix |
|---|---|
| `CONNECT tunnel failed, response 403` / `HTTP 403` from squid | Domain not in the allowlist: `sandbox blocked <name>`, then `sandbox allow <name> <domain>`. |
| A tool hangs / times out, nothing in `blocked` | The tool ignores the proxy and its direct connection is dropped silently. Configure its proxy, or set `-Djava.net.useSystemProxies=true` for JVM tools. The firewall drop counter in `sandbox blocked` increases. |
| Maven: `Could not transfer artifact … Connection timed out` | `~/.m2/settings.xml` lacks `<proxies>` (see [docs/08](08-java-kotlin.md)). |
| `git push` over SSH: `proxy refused <host>:22` | Only the host of the sandbox's SSH URL is allowed on port 22. Push to that repository only, or create another sandbox for the other repository. |
| `sandbox create`: `Use the SSH clone URL` / `Not an SSH git URL` | Pass the SSH form: `git@github.com:org/repo.git` or `ssh://git@host/org/repo.git` (port 22). |
| `sandbox auth`: `git ls-remote failed` | The deploy key is not on *this* repository yet, lacks write access, or the URL has a typo (`sandbox status <name>`). |
| `Could not resolve host` for a tool | `AGENT_DNS=block` is active and the tool resolves names itself instead of using the proxy. Configure its proxy, or as a last resort `sandbox network <name> allowlist --dns allow`. |
| Internal hosts (GHES/Nexus) unreachable | Private IPs are blocked by design. Add `ALLOW_CIDRS` (and the hostname to the allowlist), edit `~/.agent-sandbox/sandboxes/<name>/sandbox.env`, then `sandbox network <name> reload`. |
| `Egress policy is not active … refusing to start` | `sandbox network <name> reload`. If it fails, see `sudo journalctl -u agent-sandbox-network` via `sandbox shell <name> --admin`. |
| Clock skew errors (TLS "certificate not yet valid") after laptop sleep | Wait a minute for NTP, or `sandbox shell <name> --admin` → `systemctl restart systemd-timesyncd`. |

## Copilot CLI

| Symptom | Fix |
|---|---|
| Login URL/code not shown | Run `sandbox auth <name> copilot` in a real terminal (it needs a TTY). |
| Copilot fails with network errors | `sandbox blocked <name>`. New Copilot endpoints may need allowlisting. Add them to `config/allowlist/core.txt` and contribute back. |
| Copilot uses the GHES host instead of github.com | Check `COPILOT_HOST` and that `echo $COPILOT_GH_HOST` inside the VM prints `github.com`. |
| Copilot CLI asks to trust the folder | Expected the first time per directory. Answer once; it is remembered in `~/.copilot`. |
| Want a specific Copilot CLI version | `COPILOT_VERSION=x.y.z` in `sandbox.env`, then `sandbox provision <name>`. |

## Terminal

| Symptom | Fix |
|---|---|
| `open terminal failed: missing or unsuitable terminal` | Your terminal type (e.g. `xterm-ghostty`) is unknown in the VM. `agent-session` falls back to `xterm-256color` automatically; for `sandbox shell`, run `export TERM=xterm-256color`. |
| Copy/paste from tmux | Clipboard integration (OSC 52) is disabled on purpose. Use your terminal's selection, e.g. hold `Option` (iTerm2/Terminal.app) or `Shift` (most Linux terminals) while selecting. |

## Starting over

```bash
sandbox destroy <name> -y && sandbox create <name> git@github.com:<org>/<repo>.git
```

To reset everything, run `sandbox destroy` for each sandbox, then
`rm -rf ~/.agent-sandbox`. Lima itself can be removed with `brew uninstall lima` (macOS).
