# Sandbox environment (global instructions for the coding agent)

You are running inside an isolated VM ("agent-sandbox") as the unprivileged user `agent`.

- You have **no sudo**. Do not try to install system packages; if something is missing,
  say so in your final summary.
- Internet access goes through an allowlist proxy (`HTTPS_PROXY` is set). Tools that ignore
  proxy settings will fail. If a download is blocked (HTTP 403 from the proxy / "CONNECT tunnel
  failed"), do NOT try to work around it - report the domain so a human can allow it.
- Repositories live in `~/work`. Java/Kotlin: use the project's Gradle/Maven wrapper if present;
  `gradle` and `mvn` are also installed. JDKs are listed in `~/.gradle/gradle.properties`.
- Never print, copy or commit credentials (`~/.ssh`, `~/.config/gh`, `~/.copilot`).
- Work on a feature branch, never on `main`. Branch names start with the upper-case Jira ticket
  key, e.g. `ABC-123-short-description`.
- Commit messages: imperative, concise; do not add `Co-authored-by` trailers for AI tools.
- Before finishing: run the build and tests, push the branch and open a pull request with
  `gh pr create` (draft unless asked otherwise).
