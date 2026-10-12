# Extra CA certificates

Put PEM-encoded root certificates with the extension `.crt` here (for example the root CA of a
corporate TLS-inspecting proxy or of an internal Nexus/GHES). They are installed into the VM's
system trust store (and therefore into the Temurin JDK `cacerts`, Node via
`NODE_EXTRA_CA_CERTS`, git and curl) during `sandbox create` / `sandbox provision`.

`*.crt` files in this directory are git-ignored.
