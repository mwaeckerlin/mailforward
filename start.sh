#!/bin/bash -ex

# options
echo "$MAPPINGS" | sed 's/; */\n/g' >/etc/postfix/virtual
ALIAS_DOMAINS="$(sed 's, .*,,g;s,^[^@]*@,,g' /etc/postfix/virtual | sort | uniq | tr '\n' ' ')"
ALL_DOMAINS="${LOCAL_DOMAINS}${ALIAS_DOMAINS:+ ${ALIAS_DOMAINS}}"
DOMAIN=${MAILHOST:-$(echo "${ALL_DOMAINS}" | sed 's,^\([^ ]*\).*,\1,')}

# greylisting milter use GREYLIST=host:port or GREYLIST=host (default port)
if [[ -n "${GREYLIST}" && "${GREYLIST}" != *:* ]]; then
    GREYLIST="${GREYLIST}:10025"
fi
if [[ -n "${GREYLIST}" && ! "$(postconf smtpd_milters)" =~ "inet:${GREYLIST}" ]]; then
    postconf -e "smtpd_milters=inet:${GREYLIST}"
    postconf -e "non_smtpd_milters=inet:${GREYLIST}"
    postconf -e "milter_default_action=accept"
    postconf -e "milter_protocol=6"
    echo "**** Greylisting milter configured to use ${GREYLIST}"
fi

# check if letsencrypt certificates exist
if test -e /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
    -a -e /etc/letsencrypt/live/${DOMAIN}/privkey.pem; then
    postconf -e smtpd_tls_cert_file=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    postconf -e smtpd_tls_key_file=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
    postconf -e smtpd_use_tls=yes
    postconf -e smtpd_tls_security_level=may
    echo "**** TLS configured for ${DOMAIN}"
fi

postconf -e "myhostname=${DOMAIN}"
postconf -e mydestination="$LOCAL_DOMAINS"
postconf -e virtual_alias_domains="$ALIAS_DOMAINS"
postconf -e "virtual_alias_maps=hash:/etc/postfix/virtual"
postmap /etc/postfix/virtual
postalias /etc/postfix/aliases

/usr/sbin/postfix start-fg
