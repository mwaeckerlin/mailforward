# Changelog

- 2026-10-23 **1.11.2**
    - TLS on port 25 is set by `smtpd_tls_security_level` alone, `none` without a certificate and `may` with one, as before; the deprecated `smtpd_use_tls` beside it is gone
    - The deprecated `smtpd_tls_eecdh_grade = ultra` is gone: postfix 3.6 and later ignore its value and behave as with the default `auto`, so the TLS handshake does not change; postconf no longer warns about the configuration
    - The image builds without a warning of the docker build checks
    - A test starts the image without and with a certificate, checks the TLS level of each and that postconf prints no warning, in the image and in every started container

- 2026-10-23 **1.11.1**
    - The version line 1 is built and published again as `mwaeckerlin/mailforward:1`, for amd64 and arm64, on every push to this branch and every week with the run on master, so it gets the security fixes of its base images
    - Forwarding works again on current Alpine: Alpine builds postfix without Berkeley DB, so the `hash:` map type no longer exists and every alias recipient drew a temporary failure; the alias map now uses the default map type of the installed postfix
    - A test checks the image: postfix accepts its configuration, the mail system starts, every address of `MAPPINGS` is forwarded to its target, and the `GREYLIST` milter reaches the effective configuration
