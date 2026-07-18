# Changelog

- 2026-07-18 **headless image**
    - The image no longer contains a shell, busybox or a package
      manager: a compiled `init` binary configures postfix from the
      environment and starts the postfix master daemon directly. The
      behaviour (virtual-alias forwarding from `MAPPINGS`, optional
      `GREYLIST` milter, TLS when a certificate for the mail domain is
      mounted) is unchanged.
    - The old bash/telnet `health.sh` is replaced by the built-in
      `init --healthcheck` TCP probe.
    - Delivery-affecting limits are now configurable with high
      defaults: `MESSAGE_SIZE_LIMIT` (default 100 GiB) and
      `SMTP_HARD_ERROR_LIMIT` (default 20, the postfix standard — the
      previously hardcoded 1 turned a single rejected recipient into
      an abrupt disconnect for the sending server).
    - New `DISABLE_DNSBL` switch (default off) strips the DNS-blocklist
      lookups from the smtpd restrictions — for test/offline stacks
      whose resolver cannot answer the blocklist zones.
    - The virtual alias map works again on current Alpine: alpine
      builds postfix without Berkeley DB, so the historical `hash:`
      map type no longer exists — every alias recipient drew a 451
      temporary failure. The map is now compiled and looked up as
      `lmdb:` (alpine's default type), pinned by a real end-to-end
      forward test.
    - The mail queue (`/var/spool/postfix`) is now a declared volume:
      an accepted mail (`250 Ok`) is the server's responsibility and
      the sender never retries — a deferred forward must survive
      container recreates and image updates. The run example maps it
      to a named volume.
