# 3. Setup (macOS and Linux)

The setup is the same on both systems: [Lima](https://lima-vm.io) creates the VM, using Apple's
Virtualization.framework on macOS and QEMU/KVM on Linux. Only the prerequisites differ.

## Prerequisites

**macOS**

- macOS 13.5 or newer (Apple silicon recommended, Intel works).
- [Homebrew](https://brew.sh). `sandbox setup` installs Lima with it.

**Linux** (Ubuntu 22.04/24.04, Debian 12, Fedora 40+; x86_64 or aarch64)

```bash
# Debian/Ubuntu
sudo apt install -y git openssh-client netcat-openbsd qemu-system qemu-utils
# Fedora
sudo dnf install -y git openssh-clients nmap-ncat qemu-kvm qemu-img

# KVM access for your user (log out and back in afterwards)
sudo usermod -aG kvm "$USER"
grep -Ec '(vmx|svm)' /proc/cpuinfo   # > 0 on x86_64; otherwise enable VT-x/AMD-V in BIOS/UEFI
```

Then install **Lima ≥ 2.0**: <https://lima-vm.io/docs/installation/> (release tarball, or
`brew install lima` with Homebrew on Linux).

**Both:** about 15 GB of free disk per sandbox (the disk image is sparse and grows on demand,
up to `DISK_GIB`).

## One-time setup

```bash
git clone <this-repo> ~/agent-sandbox      # or copy the folder
cd ~/agent-sandbox

# optional: put the CLI on your PATH
mkdir -p ~/.local/bin && ln -s "$PWD/sandbox" ~/.local/bin/sandbox

# optional: your settings (GHES host, JDK versions, resources, ...)
cp config/sandbox.conf.example config/sandbox.conf && $EDITOR config/sandbox.conf

./sandbox setup          # macOS: installs Lima via Homebrew; Linux: checks Lima, /dev/kvm, QEMU
```

`sandbox setup` does **not** need root and changes nothing outside `~/.agent-sandbox` (and
Homebrew on macOS).

## Create your first sandbox

One sandbox works on **one repository**, given as its **SSH clone URL**:

```bash
sandbox create acme git@github.com:my-org/acme-service.git
                               # ~5–10 min the first time (Ubuntu image, JDK, Gradle, Maven, Node, Copilot CLI)
sandbox verify acme            # PASS/FAIL report: isolation + toolchain
sandbox auth acme              # 1) shows a VM-generated SSH key + the repo's deploy-key URL;
                               #    add it with write access, press Enter -> tested and cloned
                               #    into /home/agent/work/acme-service
                               # 2) gh login (fine-grained PAT) so the agent can open PRs
                               # 3) Copilot CLI login: open the URL in your host browser, enter the code
sandbox agent acme --prompt "ABC-123: implement ... Open a draft PR when done."
```

No real repository at hand? Push one of the sample projects in [`examples/`](../examples) to an
empty test repository and use its SSH URL (see [docs/08](08-java-kotlin.md#try-it-with-a-sample-project)).

See [docs/04-daily-workflow.md](04-daily-workflow.md) for the day-to-day loop.

## What gets created where

| Path | Content |
|---|---|
| `~/.agent-sandbox/sandboxes/<name>/` | `sandbox.env` (frozen settings), `id_ed25519` (host→VM SSH key, never enters the VM), `known_hosts`, `allowlist.txt`, `lima.yaml`, `review/` bundles |
| `~/.lima/agent-<name>/` | Lima's VM files (disk image, logs) |
| `~/.agent-sandbox/ssh_config` | Created by `sandbox ide` for JetBrains Gateway |
| `~/agent-review/<name>/<repo>` | Created by `sandbox fetch` for reviewing in IntelliJ |

## Notes

- **Architecture:** the VM matches your CPU — arm64 Ubuntu on Apple silicon / ARM Linux, x86_64
  otherwise. Temurin, Node, Gradle and Maven are native on both.
- **Sleep and resume:** the VM keeps running while your machine sleeps. Time inside the VM is
  corrected via NTP within a minute or so. Stop idle sandboxes with `sandbox stop <name>` to free
  RAM.
- **Corporate VPN / proxy:** the VM's traffic is NAT-ed through your host, so it follows your
  VPN routing.
  - Internal hosts, such as a GitHub Enterprise Server on a private IP, must be allowed
    explicitly with `ALLOW_CIDRS`.
  - A TLS-inspecting proxy needs its CA in `config/certs/`.
  - An explicit proxy goes in `UPSTREAM_PROXY`.
  - See [docs/05-network-policy.md](05-network-policy.md).
- **Linux: Docker / ufw / firewalld** on the host do not interfere: Lima uses user-mode
  networking (no bridges, TAP devices or host firewall rules).
- **Linux: dedicated user.** For an extra layer, run the sandboxes under a separate Linux user
  with nothing in its home directory.
