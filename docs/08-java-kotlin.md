# 8. Java / Kotlin with Gradle and Maven

## What is installed in the VM

| Tool | Version (default) | Source | Configured by |
|---|---|---|---|
| Temurin JDK | `JDK_VERSIONS="21"` (e.g. `"21 25 17"`) | Adoptium apt repo | first entry = `JAVA_HOME` + `update-alternatives` |
| Gradle | `GRADLE_VERSION=9.8.1` | services.gradle.org (SHA-256 verified) | `/opt/gradle`, `gradle` on PATH |
| Maven | `MAVEN_VERSION=3.9.16` | archive.apache.org (SHA-512 verified) | `/opt/maven`, `mvn` on PATH |
| Node.js | `NODE_MAJOR=24` | NodeSource apt repo | needed by Copilot CLI |
| Copilot CLI | latest (`COPILOT_VERSION`) | npm `@github/copilot` (installed by root) | `copilot` on PATH |
| gh, git, git-lfs, tmux, jq, ripgrep | Ubuntu / GitHub apt | | |

All JDKs are listed in `org.gradle.java.installations.paths`, so **Gradle toolchains**
(`jvmToolchain(17)`, `21`, `25`, …) find them without downloading anything. If a project asks
for a JDK that is not installed, Gradle tries to auto-provision it via foojay/Adoptium
(`api.foojay.io` and `api.adoptium.net` are in the `java` allowlist). It is better to add the
version to `JDK_VERSIONS` and run `sandbox provision`.

## Proxy configuration (done for you)

`~/.gradle/gradle.properties` (managed block, your own lines outside it are kept):

```properties
systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=3128
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=3128
systemProp.http.nonProxyHosts=localhost|127.*|[::1]
systemProp.https.nonProxyHosts=localhost|127.*|[::1]
org.gradle.java.installations.paths=/usr/lib/jvm/temurin-21-jdk-arm64
```

`~/.m2/settings.xml` (generated only if you don't provide one via `config/home/.m2/settings.xml`):

```xml
<proxies>
  <proxy><id>sandbox-http</id><active>true</active><protocol>http</protocol>
    <host>127.0.0.1</host><port>3128</port><nonProxyHosts>localhost|127.*</nonProxyHosts></proxy>
  <proxy><id>sandbox-https</id><active>true</active><protocol>https</protocol>
    <host>127.0.0.1</host><port>3128</port><nonProxyHosts>localhost|127.*</nonProxyHosts></proxy>
</proxies>
```

> If you bring your own `settings.xml` (Nexus mirror), **copy this `<proxies>` block into it**.
> Without it, Maven tries direct connections, which the firewall drops.

## Corporate Nexus / Artifactory

```bash
# config/sandbox.conf
EXTRA_ALLOW_DOMAINS="nexus.corp.example"
ALLOW_CIDRS="10.20.30.40/32"            # only if nexus.corp.example has a private IP
```

`config/home/.m2/settings.xml`:

```xml
<settings>
  <mirrors>
    <mirror><id>nexus</id><mirrorOf>*</mirrorOf><url>https://nexus.corp.example/repository/maven-public/</url></mirror>
  </mirrors>
  <proxies><!-- the two sandbox proxies from above --></proxies>
  <!-- prefer a read-only token for the mirror; the agent can read this file -->
</settings>
```

`config/home/.gradle/init.d/nexus.gradle.kts`:

```kotlin
settingsEvaluated {
    pluginManagement.repositories { clear(); maven("https://nexus.corp.example/repository/gradle-plugins/") }
    dependencyResolutionManagement.repositories { clear(); maven("https://nexus.corp.example/repository/maven-public/") }
}
allprojects {
    repositories { clear(); maven("https://nexus.corp.example/repository/maven-public/") }
}
```

With a mirror for everything you can shrink the allowlist (`ALLOWLISTS="core"` +
`EXTRA_ALLOW_DOMAINS="nexus.corp.example services.gradle.org"`). That is the tightest
setup: one artifact source, fully audited by your Nexus.

Corporate CA for Nexus over TLS: put it into `config/certs/` (it is added to the system store,
which the Temurin packages sync into their `cacerts`).

## Tips

- **Gradle daemon memory.** The default VM has 8 GiB. For big builds set
  `org.gradle.jvmargs=-Xmx4g` in the project, or `--memory 12` when creating the sandbox.
- **Caches** (`~/.gradle/caches`, `~/.m2/repository`) live inside the VM and persist until
  `sandbox destroy`.
- **Testcontainers / Docker builds:** Docker is intentionally not installed, because the docker
  group is root-equivalent and would bypass the egress policy. If you really need it, use
  rootless Docker or Podman for the `agent` user and add the registries to the allowlist.
  Understand that the isolation is then weaker *inside* the VM (the VM boundary is unchanged).
