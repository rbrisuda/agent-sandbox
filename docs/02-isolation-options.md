# 2. Isolation options: why a VM, and why Lima

| Option | Isolation boundary | macOS | Linux | Notes |
|---|---|---|---|---|
| Nothing (agent on host) | none | ✔ | ✔ | Agent = you. All files, keys, VPN. |
| `copilot --sandbox` / Seatbelt / bubblewrap | process sandbox, same kernel | ✔ | ✔ | Good extra layer and quick to use, but it is policy-based. Every allowed path or bypass prompt is a hole, and it shares the host kernel. |
| Dev container / Docker | namespaces, **shared kernel** | ✔ (Docker Desktop runs a VM anyway) | ✔ | Bind-mounting the repo exposes the host folder. On Linux, a kernel bug can lead to host compromise. |
| gVisor (runsc) | user-space kernel | ✗ | ✔ | Strong, but Linux only and has compatibility gaps. |
| **Full VM** (Apple Virtualization.framework, QEMU/KVM) | hardware virtualization | ✔ | ✔ | Separate kernel, its own disk, and nothing shared unless you configure it. |
| **Firecracker microVM** | hardware virtualization (KVM) and a minimal VMM | ✗ (no KVM) | ✔ | Same model as AWS Lambda/Fargate. Tiny attack surface (about 5 emulated devices, Rust, seccomp), boots in under a second. |
| Kata Containers | microVM per container | ✗ | ✔ | Firecracker/Cloud Hypervisor under a container runtime. More moving parts. |

## Why Lima on both macOS and Linux?

Firecracker has the smallest attack surface, but it needs **Linux KVM**. macOS has no KVM, so on
a Mac it would only run nested inside another Linux VM (supported on Apple M3/M4 with macOS 15+),
which adds a second hypervisor without a security gain: the outer VM is already the boundary
that protects your Mac.

[Lima](https://lima-vm.io) runs the same Ubuntu VM on both systems with one configuration:

| Host | Hypervisor |
|---|---|
| macOS 13.5+ (Apple silicon or Intel) | Apple **Virtualization.framework** (`vmType: vz`), the same technology Docker Desktop and Apple's `container` tool use |
| Linux with `/dev/kvm` | **QEMU + KVM** (`vmType: qemu`) |

One code path means one set of instructions, one thing to test, no `sudo`, and the same
behaviour for everyone on the team. Both are full hardware-virtualized VMs with their own kernel.

## Hardening applied to the Lima VM

Lima is designed for convenience: by default it mounts your home directory, forwards ports and
can forward your SSH agent. This project generates a Lima config that switches all of that off:

| Setting | Value | Why |
|---|---|---|
| `plain: true` | | No guest agent, no automatic port forwarding, no mounts, no containerd. |
| `mounts: []` | | Your home directory is **not** visible in the VM. |
| `ssh.forwardAgent` | `false` | Your SSH keys cannot be used from the VM. |
| `ssh.loadDotSSHPubKeys` | `false` | Your `~/.ssh/*.pub` are not copied in. |
| `ssh.forwardX11` | `false` | |
| `portForwards` | ignore all | Nothing in the VM is exposed on your host. |
| `propagateProxyEnv` | `false` | Your host proxy settings (which may include credentials) are not copied. |
| `ssh.overVsock` | `false` | SSH goes through a fixed localhost port, which is predictable for the IDE. |

Remaining host ↔ VM channels:

- SSH from the host into the VM (the host initiates; the VM cannot connect to the host).
- The NAT network:
  - The VM sees the host as `192.168.5.2`.
  - The egress firewall blocks this address and all private ranges for the agent.

## Possible future hardening: Firecracker on Linux

Not implemented (deliberately, to keep one setup for macOS and Linux). What it would add on
Linux hosts:

- **Minimal VMM.** Firecracker emulates only a handful of devices (virtio-net, virtio-block,
  serial, vsock, entropy) in a seccomp-confined Rust process, instead of QEMU's much larger
  device model. Less code exposed to the guest means fewer possible VM-escape bugs.
- **Host-enforced network policy.** Each VM would get its own TAP device and nftables table on
  the host, dropping traffic to the host, other sandboxes and private/metadata ranges. Those
  rules live outside the VM, so they hold even if the agent gains root in the guest.
- **`jailer`** (chroot, own uid/gid, cgroups, namespaces) for the VMM process.

The cost: a separate backend (kernel + rootfs image build, TAP/nftables setup with `sudo`,
interaction with Docker/ufw/firewalld), which only works on Linux. The guest provisioning in
this project is backend-independent, so it could be added later behind the same CLI.

## Combining layers

The layers stack. You can still run `copilot --sandbox` *inside* the VM if you want an extra
process-level policy. The VM is the boundary that protects your machine; the in-VM firewall and
proxy limit what a compromised session can reach on the internet.
