# Home overlay for the `agent` user

Everything in this directory (except this README) is copied into `/home/agent` inside the VM on
`sandbox create` / `sandbox provision`. Typical uses:

| File                              | Purpose                                                        |
|-----------------------------------|----------------------------------------------------------------|
| `.m2/settings.xml`                | Corporate Nexus mirror. **Must keep a `<proxies>` section** pointing to `127.0.0.1:3128` (see `docs/08-java-kotlin.md`). |
| `.gradle/init.d/mirror.gradle.kts`| Redirect Gradle repositories to a Nexus mirror.                 |
| `.copilot/copilot-instructions.md`| Your own global agent instructions (replaces the default one).  |
| `.gitconfig`                      | Extra git settings (user name/email are set by the sandbox).    |

Do **not** put secrets here unless you accept that the agent can read them — everything in
`/home/agent` is readable by the agent (that is the point of the overlay). Prefer scoped,
revocable tokens (see `docs/06-credentials.md`).

Everything in this directory except this README is git-ignored.
