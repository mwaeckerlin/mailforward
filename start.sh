#!/bin/bash -ex

# options
DOMAIN=${MAILHOST:-$(sed 's,^[^@]*@\([^ ]*\).*,\1,' <<<${MAPPINGS})}

# greylist filter use --link geylist-container:postgrey
GREYLIST=""
if test -n "${POSTGREY_PORT_10023_TCP_ADDR}"; then
    GREYLIST=", check_policy_service inet:${POSTGREY_PORT_10023_TCP_ADDR}:10023"
    postconf -e "$(postconf smtpd_client_restrictions)${GREYLIST}"
fi

# check if letsencrypt certificates exist
if test -e /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
        -a -e /etc/letsencrypt/live/${DOMAIN}/privkey.pem; then
    postconf -e smtpd_tls_cert_file=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    postconf -e smtpd_tls_key_file=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
    postconf -e smtpd_use_tls=yes
    postconf -e smtpd_tls_security_level=encrypt
fi

# virtual hosts
postconf -e "myhostname=${DOMAIN}"
postconf -e "virtual_alias_maps=hash:/etc/postfix/virtual"
sed 's/, */\n/g' <<<"$MAPPINGS" > /etc/postfix/virtual
postconf -e virtual_alias_domains="$(sed 's, .*,,g;s,^[^@]*@,,g' /etc/postfix/virtual | sort | uniq | tr '\n' ' ')"
postmap /etc/postfix/virtual

service syslog-ng restart
service postfix restart
tail -F /var/log/mail.log
