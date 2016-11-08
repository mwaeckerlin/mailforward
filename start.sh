#!/bin/bash -ex

postconf -e virtual_alias_domains="${DOMAINS}"
postconf -e mydestination="${DOMAINS}"
postconf -e "virtual_alias_maps=hash:/etc/postfix/virtual"
#postconf -d "myhostname=${MAILHOST}"
echo "${MAPPINGS}" | sed 's/, */\n/g' > /etc/postfix/virtual
postmap /etc/postfix/virtual
service postfix restart
sleep infinity
