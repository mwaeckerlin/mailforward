#!/bin/bash -ex

postconf -e virtual_alias_domains="${DOMAINS}"
echo "${MAPPINGS}" | sed 's/, */\n/g' > /etc/postfix/virtual
postmap /etc/postfix/virtual
service postfix restart
sleep infinity

