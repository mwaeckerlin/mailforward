#!/bin/bash -ex

postconf -e virtual_alias_domains="${DOMAINS}"
postconf -e mydestination="${DOMAINS}"
echo "${MAPPINGS}" | sed 's/, */\n/g' > /etc/postfix/virtual
postmap /etc/postfix/virtual
service rsyslog start
service postfix restart
sleep infinity
