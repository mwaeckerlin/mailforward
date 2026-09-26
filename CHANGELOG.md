# Changelog

- 2026-09-26 **3.5.1**
    - The image builds on arm64 as well as on amd64 and is published for both under one tag, built and published automatically on every change and every week

- 2026-07-20 **opportunistic TLS floor relaxed**
    - The TLS 1.2 floor now applies only to the mandatory TLS paths (authenticated / enforced TLS). Opportunistic inbound and outbound TLS keep every protocol except the broken SSLv2/SSLv3, so a legacy peer's mail is still encrypted rather than forced back to plaintext by a hard floor (RFC 7435; delivery before filtering). This `main.cf` is inherited by mwaeckerlin/postfix.
    - README: the greylisting example now notes that the companion postgrey image is deprecated (use the full mailservice/rspamd stack instead).

- 2026-07-18 **security hardening**
    - Every configuration value from the environment is now validated before use; a malformed value (for example an embedded newline that could smuggle extra configuration directives into the alias map or the postfix configuration) refuses to start with a clear `invalid <VAR>` error. Covered by the new config-validation test suite (`npm test`).
    - TLS setup modernised: the deprecated `smtpd_use_tls` / `smtpd_tls_eecdh_grade` switches and the hand-rolled 2015-era cipher list are gone (postfix's maintained defaults are stronger); the protocol floor is now TLS 1.2. STARTTLS stays opportunistic, so a legacy sender without TLS 1.2 falls back to plaintext and the mail still arrives — delivery before filtering.
    - The greylisting example in the README no longer publishes the milter port on the host and uses the milter-greylist port (10025) instead of the retired postgrey policy port.
    - New standalone compose example (loopback only, with healthcheck and persistent queue volume).

- 2026-07-18 **headless image**
    - The image no longer contains a shell, busybox or a package manager: a compiled `init` binary configures postfix from the environment and starts the postfix master daemon directly. The behaviour (virtual-alias forwarding from `MAPPINGS`, optional `GREYLIST` milter, TLS when a certificate for the mail domain is mounted) is unchanged.
    - The old bash/telnet `health.sh` is replaced by the built-in `init --healthcheck` TCP probe.
    - Delivery-affecting limits are now configurable with high defaults: `MESSAGE_SIZE_LIMIT` (default 100 GiB) and `SMTP_HARD_ERROR_LIMIT` (default 20, the postfix standard — the previously hardcoded 1 turned a single rejected recipient into an abrupt disconnect for the sending server).
    - New `DISABLE_DNSBL` switch (default off) strips the DNS-blocklist lookups from the smtpd restrictions — for test/offline stacks whose resolver cannot answer the blocklist zones.
    - The virtual alias map works again on current Alpine: alpine builds postfix without Berkeley DB, so the historical `hash:` map type no longer exists — every alias recipient drew a 451 temporary failure. The map is now compiled and looked up as `lmdb:` (alpine's default type), pinned by a real end-to-end forward test.
    - The mail queue (`/var/spool/postfix`) is now a declared volume: an accepted mail (`250 Ok`) is the server's responsibility and the sender never retries — a deferred forward must survive container recreates and image updates. The run example maps it to a named volume.
