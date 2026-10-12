# 6. Credentials

Rule: **nothing from your host's credential stores goes into the VM.** Credentials used in the
VM are created *for* the VM, scoped as narrowly as possible, and easy to revoke.

| Credential | Created where | Scope | Revoke |
|---|---|---|---|
| Host → VM SSH key (`~/.agent-sandbox/sandboxes/<n>/id_ed25519`) | host, by `sandbox create` | Only lets *you* log into the VM. The private key never enters the VM. | `sandbox destroy` |
| Git SSH key (`/home/agent/.ssh/id_ed25519_git`) | **inside the VM** | Add it as a **deploy key with write access** on one repository | Repo → Settings → Deploy keys |
| `gh` token | you paste it in the VM | **Fine-grained PAT**: one repository; *Contents* R/W, *Pull requests* R/W, *Metadata* R | GitHub → Settings → Developer settings → Tokens |
| Copilot CLI token | device login in the VM (`copilot login`) or `COPILOT_GITHUB_TOKEN` | Copilot requests only (a fine-grained PAT with the *Copilot Requests* permission works) | GitHub → Settings → Applications / Tokens |

`sandbox auth <name>` walks you through all three. Because the sandbox knows its repository
(the SSH URL from `sandbox create`), the git step prints the exact deploy-key page
(`https://<host>/<org>/<repo>/settings/keys/new`), verifies access with `git ls-remote`, and
clones the repository into `~/work`. Use `sandbox auth <name> git|gh|copilot`
for a single step, or `status` to check what is set up.

## Why a deploy key and not your personal SSH key?

Your personal key can push to **every** repository you have access to, and it signs in as you
everywhere. A deploy key works for one repository only, and you can see it and delete it in that
repository's settings. If the VM is compromised, the damage is limited to a branch in that repo,
and branch protection on `main` (required reviews, required checks) stops the rest.

If you need several repositories, use one of these:

- One sandbox per repository (recommended).
- A **machine user** with access to just those repositories.

## Pushing is fine; merging is not the agent's job

You told us branch protection exists on `main`. Make sure it includes:

- [x] Require a pull request before merging, with at least 1 approval
- [x] Require status checks to pass
- [x] Do not allow bypassing the above settings (also for admins). This matters because a
      fine-grained PAT of an admin could otherwise merge.
- [x] Restrict force pushes and deletions
- Optional: a ruleset requiring branch names like `[A-Z]+-[0-9]+-*`, to enforce the Jira-key
  convention.

## GitHub Enterprise Server + Copilot on github.com

Common setup: code and PRs live on GHES (e.g. `github.com`), while Copilot is licensed
through github.com.

```bash
# config/sandbox.conf
GIT_HOST=github.com
GH_HOST=github.com
COPILOT_HOST=github.com
```

Inside the VM:

- `GH_HOST=github.com`, so `gh pr create` targets your GHES.
- `COPILOT_GH_HOST=github.com` makes the Copilot CLI authenticate against github.com
  regardless of `GH_HOST`.

For a GHE.com (data residency) tenant, use `COPILOT_HOST=<tenant>.ghe.com`.

If the GHES resolves to a private IP, add its range to `ALLOW_CIDRS`
(see [docs/05](05-network-policy.md#corporate-environments)).

## Where tokens end up inside the VM

The VM has no OS keyring, so `gh` and Copilot CLI store tokens in plaintext files under
`/home/agent` (`~/.config/gh/hosts.yml`, `~/.copilot/`). The **agent can read them**. This
is unavoidable (the agent needs them to work), which is why the tokens must be narrowly scoped.
They are never on your host, and they disappear with `sandbox destroy`. Revoke them as well.

## Rotating

```bash
sandbox destroy acme          # removes VM, keys and tokens in it
# revoke: deploy key, fine-grained PAT, Copilot device authorization
sandbox create acme git@github.com:my-org/acme-service.git && sandbox auth acme
```
