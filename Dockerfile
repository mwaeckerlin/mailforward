# Inherits the accumulated postfix configuration (main.cf) from the
# published mwaeckerlin/smtp-relay image — a locally built image takes
# precedence, otherwise Docker pulls it from the hub. The build stage
# installs postfix fresh (very-base has the package manager the
# headless parent no longer ships) and layers this image's deltas on
# the parent's main.cf.
FROM mwaeckerlin/smtp-relay AS parent

FROM mwaeckerlin/very-base AS init
RUN $PKG_INSTALL g++
COPY init.cpp .
RUN g++ -static -Os -flto=auto -fno-rtti -ffunction-sections -fdata-sections \
        -Wl,--gc-sections -Wl,-s -std=c++20 -o init init.cpp
RUN strip -s -R .comment -R .gnu.version --strip-unneeded init

FROM mwaeckerlin/very-base AS build
RUN $PKG_INSTALL postfix ca-certificates
RUN mkdir /mail
RUN $ALLOW_USER /mail
RUN mkdir -p /tmp
RUN chmod 1777 /tmp
COPY --from=parent /etc/postfix/main.cf /etc/postfix/main.cf
RUN postconf -e mydestination="localhost"
RUN postconf -e smtpd_use_tls=no
RUN postconf -e smtpd_tls_security_level=none
# secure tls https://blog.tinned-software.net/harden-the-ssl-configuration-of-your-mailserver/
RUN postconf -e smtpd_tls_auth_only=yes
RUN postconf -e 'smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3'
RUN postconf -e 'smtpd_tls_protocols = !SSLv2 !SSLv3'
RUN postconf -e smtpd_tls_mandatory_ciphers=high
RUN postconf -e 'tls_high_cipherlist=EDH+CAMELLIA:EDH+aRSA:EECDH+aRSA+AESGCM:EECDH+aRSA+SHA384:EECDH+aRSA+SHA256:EECDH:+CAMELLIA256:+AES256:+CAMELLIA128:+AES128:+SSLv3:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXP:!PSK:!DSS:!RC4:!SEED:!ECDSA:CAMELLIA256-SHA:AES256-SHA:CAMELLIA128-SHA:AES128-SHA'
RUN postconf -e smtpd_tls_eecdh_grade=ultra
# SPAM Prevention. smtpd_hard_error_limit is set at start-up from the
# SMTP_HARD_ERROR_LIMIT env (see init.cpp) with the postfix standard
# default of 20 — the previously hardcoded 1 turned a single 5xx into
# an abrupt 421.
RUN postconf -e smtpd_helo_required='yes'
RUN postconf -e smtpd_helo_restrictions='permit_sasl_authenticated, reject_invalid_hostname, reject_non_fqdn_hostname, reject_unauth_pipelining'
RUN postconf -e smtpd_sender_restrictions='permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_sender, reject_unauth_pipelining'
RUN postconf -e smtpd_recipient_restrictions='permit_sasl_authenticated, permit_mynetworks, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org'
RUN postconf -e smtpd_client_restrictions='reject_invalid_hostname, reject_rhsbl_sender dbl.spamhaus.org, reject_rhsbl_client dbl.spamhaus.org, reject_rhsbl_helo dbl.spamhaus.org'
RUN postconf -e strict_rfc821_envelopes='yes'
RUN postconf -e smtpd_relay_restrictions='permit_sasl_authenticated, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org'
# master execs every service directly — no chroot jail exists in the
# headless image, so normalize all master.cf entries to chroot=n.
RUN postconf -F '*/*/chroot=n'
RUN newaliases
COPY --from=init init /usr/bin/init
# These are shell scripts driven by the postfix(1) wrapper — the
# headless image boots master directly via init, so they must not ship.
RUN rm -f /usr/libexec/postfix/postfix-script \
          /usr/libexec/postfix/post-install \
          /usr/libexec/postfix/postfix-wrapper \
          /usr/libexec/postfix/postfix-tls-script \
          /usr/libexec/postfix/postmulti-script

# Collect only the binaries, shared libraries and configs the runtime
# actually needs into /root/ — no shell, no package manager, no
# busybox. musl's `ldd` accepts exactly ONE file per invocation, so
# deps are gathered in a per-file loop; /lib/ld-musl-x86_64.so.1 is
# the ELF interpreter and listed explicitly.
RUN tar cph \
        /etc/postfix /var/spool/postfix /var/lib/postfix /mail \
        /etc/passwd /etc/group /etc/services /etc/nsswitch.conf \
        /etc/ssl/certs /etc/ssl/cert.pem /usr/share/ca-certificates \
        /usr/sbin/postconf /usr/sbin/postmap /usr/sbin/postalias \
        /usr/sbin/postsuper /usr/sbin/postlog /usr/sbin/postqueue \
        /usr/sbin/postdrop /usr/sbin/postcat /usr/sbin/sendmail \
        /usr/libexec/postfix /usr/lib/postfix \
        /usr/share/icu \
        /usr/bin/init /lib/ld-musl-x86_64.so.1 /tmp \
        $(for f in /usr/sbin/post* /usr/sbin/sendmail \
                   /usr/libexec/postfix/* /usr/lib/postfix/*.so*; do \
              ldd "$f" 2>/dev/null | sed -n 's,.* => \([^ ]*\) .*,\1,p'; \
          done | sort -u) \
    | tar xpC /root/

FROM mwaeckerlin/scratch
ENV CONTAINERNAME="mailforward" \
    MAILHOST="" \
    MAPPINGS="" \
    LOCAL_DOMAINS="" \
    GREYLIST="" \
    DISABLE_DNSBL="" \
    MESSAGE_SIZE_LIMIT="107374182400" \
    SMTP_HARD_ERROR_LIMIT="20"
EXPOSE 25
VOLUME /etc/letsencrypt
# The mail queue MUST be persistent: postfix answers 250 as soon as a
# mail is fsync'ed into the queue — from then on the server owns
# delivery and the sender never retries. A deferred forward sitting
# here through a container recreate would otherwise vanish silently.
# Map this to a NAMED volume in production (an anonymous one does not
# survive `down`).
VOLUME /var/spool/postfix
# Trade-off: the postfix master process must start as root to bind
# port 25 and manage the queue; every service then drops privileges to
# the postfix user per master.cf. See README.
USER root
ENTRYPOINT ["/usr/bin/init"]
COPY --from=build /root/ /
