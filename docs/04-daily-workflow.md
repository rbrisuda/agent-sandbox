# 4. Daily workflow

```mermaid
sequenceDiagram
  actor You
  participant Host as sandbox CLI (host)
  participant VM as Sandbox VM
  participant GH as GitHub
  You->>Host: sandbox agent acme --prompt "ABC-123 ..."
  Host->>VM: SSH (agent user) → tmux → copilot --yolo
  VM->>VM: edits, gradle build, tests (deps via proxy)
  VM->>GH: git push ABC-123-... (deploy key) + gh pr create
  You->>Host: Ctrl-b d (detach) … later: sandbox agent acme (re-attach)
  You->>Host: sandbox fetch acme
  Host->>You: branches in ~/agent-review/acme/... → review in IntelliJ / on GitHub
```

## Start a task

```bash
sandbox agent acme --prompt "ABC-123: add pagination to GET /orders. Run ./gradlew test. Open a draft PR."
# or from a file
sandbox agent acme --prompt-file ~/tasks/ABC-123.md
# or interactive, no initial prompt
sandbox agent acme
```

What happens:

- The VM starts if it is stopped.
- The prompt is copied into the VM (`~/.agent-sandbox/prompts/`).
- If the repository is not cloned yet, it is cloned now (needs the deploy key from `sandbox auth`).
- A **tmux** session `agent-<repo>` starts in `~/work/<repo>`, running `AGENT_CMD`
  (`copilot --yolo` by default) with the prompt.
- The agent refuses to start if the egress policy is not active (fail closed).

### Detach and re-attach

| Action | How |
|---|---|
| Detach (agent keeps working) | `Ctrl-b d` |
| Re-attach | `sandbox agent acme` (same command) |
| Another repository | Create another sandbox: `sandbox create other git@github.com:my-org/other.git` (one repo + deploy key per sandbox) |
| Agent finished | You land in a shell in the repository. Run `agent-run .` to start the agent again, or `exit`. |

### Copilot CLI permissions inside the VM

`--yolo` (= `--allow-all-tools --allow-all-paths --allow-all-urls`) is reasonable **inside** the
sandbox, because the VM is the permission boundary. To keep some prompts, set e.g.
`AGENT_CMD="copilot --allow-all-tools"` in `config/sandbox.conf`.

## Watch, inspect, intervene

```bash
sandbox shell acme                  # second shell as 'agent' (e.g. run tests yourself)
sandbox exec acme -- git -C ~/work/acme-service log --oneline -5
sandbox blocked acme                # what did the proxy deny? (missing allowlist entries)
sandbox allow acme registry.npmjs.org
```

## Get the results

The agent usually pushes a branch and opens a PR (with `gh`). You can review in three ways:

1. **On GitHub (simplest):** review the PR in the web UI and let CI run.
2. **Locally, without executing anything:** run `sandbox fetch acme`.
   - It creates a `git bundle` inside the VM and fetches it into `~/agent-review/acme/<repo>` on
     your host as `sandbox/<branch>`.
   - This also works for branches the agent did not push.
   - See [docs/07](07-reviewing-in-intellij.md).
3. **Remote IDE:** `sandbox ide acme` lets JetBrains Gateway open the project *inside* the VM.

## Give the agent a file

```bash
sandbox put acme ./spec/ABC-123.pdf ./api.yaml     # -> /home/agent/inbox/
```

This is the **only** way host files get into the VM, and it is explicit.

## Housekeeping

```bash
sandbox list
sandbox stop acme                   # frees RAM; disk is kept
sandbox start acme
sandbox destroy acme                # VM + disk gone. Revoke the deploy key / PAT afterwards.
sandbox provision acme              # re-apply guest config after changing config/ or guest/
```

**Recommended lifecycle:** one sandbox per repository (or per project). Destroy and recreate
it periodically, and always after anything suspicious. Creating a new sandbox takes about
5–10 minutes.
