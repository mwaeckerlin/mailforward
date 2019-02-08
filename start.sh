#!/bin/bash -ex

# options
sed 's/; */\n/g' <<<"$MAPPINGS" > /etc/postfix/virtual
ALIAS_DOMAINS="$(sed 's, .*,,g;s,^[^@]*@,,g' /etc/postfix/virtual | sort | uniq | tr '\n' ' ')"
ALL_DOMAINS="${LOCAL_DOMAINS}${ALIAS_DOMAINS:+ ${ALIAS_DOMAINS}}"
DOMAIN=${MAILHOST:-$(sed 's,^\([^ ]*\).*,\1,' <<<${ALL_DOMAINS})}

# greylist filter use GREYLIST=host:port or --link greylist-container:postgrey
if test -n "${GREYLIST:-${POSTGREY_PORT_10023_TCP_ADDR}}"; then
    postconf -e "$(postconf smtpd_client_restrictions), check_policy_service inet:${GREYLIST:-${POSTGREY_PORT_10023_TCP_ADDR}:10023}"
fi

# check if letsencrypt certificates exist
if test -e /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
        -a -e /etc/letsencrypt/live/${DOMAIN}/privkey.pem; then
    postconf -e smtpd_tls_cert_file=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    postconf -e smtpd_tls_key_file=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
    postconf -e smtpd_use_tls=yes
    postconf -e smtpd_tls_security_level=may
fi

postconf -e "myhostname=${DOMAIN}"
postconf -e mydestination="$LOCAL_DOMAINS"
postconf -e virtual_alias_domains="$ALIAS_DOMAINS"
postconf -e "virtual_alias_maps=hash:/etc/postfix/virtual"
postmap /etc/postfix/virtual

touch /var/log/mail.log
/usr/sbin/dsyslog
service postfix restart
tail -F /var/log/mail.log
