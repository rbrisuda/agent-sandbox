# 7. Reviewing the agent's work in IntelliJ IDEA

> ⚠️ **The important part:** opening a Gradle or Maven project in IntelliJ normally **runs its
> build logic on your machine**:
>
> - Gradle sync executes `build.gradle.kts`, `settings.gradle.kts`, `buildSrc` and plugins.
> - Maven import resolves and can run extensions.
>
> Code written by the agent must therefore never be imported as a trusted project on your host.
> Choose one of the options below.

| Option | Where code is executed | Comfort | Setup |
|---|---|---|---|
| **A. GitHub PR review** | nowhere (CI runs it) | good diff UI, no navigation | none |
| **B. Fetch + IntelliJ Safe Mode** | nowhere (read-only browsing) | full editor, diffs, history; no code insight that needs the build model | `sandbox fetch` |
| **C. JetBrains Gateway into the VM** | inside the VM | full IDE: navigation, run tests, debug | `sandbox ide`, plus the IDE backend download in the VM |

## A. Review the pull request

The agent pushes a branch and opens a draft PR. Review it like any external contribution.
Required CI checks run the build in your CI environment, not on your laptop.

## B. Fetch into a local review repository + Safe Mode

```bash
sandbox fetch acme                         # the sandbox's repository (from the SSH URL)
# -> ~/agent-review/acme/acme-service  with remote-tracking branches sandbox/<branch>
```

How it works:

- A `git bundle` (a single file of git objects) is created inside the VM, streamed to the host
  over SSH, and `git fetch`ed into a **separate review repository**. Your own working copy is
  never touched.
- Fetching runs no code: hooks and filters from the repository are not executed.

In IntelliJ:

1. **File → Open…** → `~/agent-review/acme/acme-service`
2. When asked *"Trust and open project?"*, choose **Preview in Safe Mode**. In Safe Mode,
   IntelliJ does not import Gradle/Maven, does not run build scripts and does not execute run
   configurations.
3. **Git → Branches → `sandbox/ABC-123-…` → Compare with Current** (or **Show Diff with
   Working Tree**), or open the **Git log** tool window and select the branch.
4. Add your comments on GitHub, or continue the conversation with the agent
   (`sandbox agent acme`).

Also disable *Settings → Build Tools → "Reload changes in build scripts: Any changes"* for
projects you haven't trusted, and keep **Settings → Advanced Settings → "Trust projects in
…"** empty for `~/agent-review`.

If you want to *run* the agent's code, do it in the VM (`sandbox shell acme` → `./gradlew test`),
not on the host.

## C. JetBrains Gateway / Remote Development (full IDE, code stays in the VM)

```bash
sandbox ide acme
```

This command:

- writes `~/.agent-sandbox/ssh_config` with a `Host sandbox-acme` entry. The entry uses the
  sandbox key, sets no agent forwarding and pins the host key.
- prints the line to add as the **first line** of `~/.ssh/config`:
  `Include ~/.agent-sandbox/ssh_config`.

Then:

1. Allow the IDE backend download: `sandbox allow acme .jetbrains.com download-cdn.jetbrains.com plugins.jetbrains.com`
   (or add `jetbrains` to `ALLOWLISTS` before creating the sandbox).
2. Open **JetBrains Gateway**, or in IntelliJ **File → Remote Development → SSH**:
   - New connection → host `sandbox-acme`, user `agent`, authentication "OpenSSH config and
     authentication agent".
   - IDE: IntelliJ IDEA. Project: `/home/agent/work/acme-service`.
3. The IDE backend runs **inside the VM** as `agent`. Gradle sync, indexing, tests and the
   debugger all run there. Only the UI runs on your Mac.

Trade-offs:

- Needs RAM in the VM; the IDE backend wants 2–4 GB. Consider `--memory 12`.
- The backend runs as the same user as the agent. A malicious agent session could tamper with
  the backend's files while you are connected. The worst case is still contained in the VM, but
  don't use the remote IDE to paste host secrets into the VM.
  - Hardening idea: a separate `reviewer` user in the VM.
- The SSH channel allows *local* port forwarding (needed by Gateway), from your Mac into the VM
  only. The VM cannot open ports on your Mac.

## VS Code

The same options apply:

- Option B: use **Restricted Mode** when VS Code asks whether you trust the folder.
- Option C: use **Remote-SSH** with host `sandbox-acme`.
