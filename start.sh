#!/bin/bash -ex

# options
# greylist filter use --link geylist-container:postgrey
GREYLIST=""
if test -n "${POSTGREY_PORT_10023_TCP_ADDR}"; then
    GREYLIST=", check_policy_service inet:${POSTGREY_PORT_10023_TCP_ADDR}:10023"
fi

# general settings
postconf -e compatibility_level=2
postconf -e virtual_alias_domains="${DOMAINS}"
postconf -e mydestination="${DOMAINS}"
postconf -e "myhostname=${MAILHOST}"

# SPAM prevention
postconf -e smtpd_hard_error_limit='1'
postconf -e smtpd_helo_required='yes'
postconf -e smtpd_helo_restrictions='permit_tls_clientcerts, permit_sasl_authenticated, permit_mynetworks, reject_invalid_hostname, reject_non_fqdn_hostname, reject_unauth_pipelining'
postconf -e smtpd_sender_restrictions='permit_mynetworks, permit_tls_clientcerts, permit_sasl_authenticated, reject_non_fqdn_sender, reject_unauth_pipelining'
postconf -e smtpd_recipient_restrictions='permit_tls_clientcerts, permit_sasl_authenticated, permit_mynetworks, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org'"${GREYLIST}"
postconf -e smtpd_client_restrictions='reject_invalid_hostname, reject_rhsbl_sender dbl.spamhaus.org, reject_rhsbl_client dbl.spamhaus.org, reject_rhsbl_helo dbl.spamhaus.org'
postconf -e strict_rfc821_envelopes='yes'

# virtual hosts
postconf -e "virtual_alias_maps=hash:/etc/postfix/virtual"
echo "${MAPPINGS}" | sed 's/, */\n/g' > /etc/postfix/virtual
postmap /etc/postfix/virtual

# setup logging
! test -e /var/log/mail.log || rm /var/log/mail.log
ln -sf /proc/self/fd/1 /var/log/mail.log

service postfix restart
sleep infinity
