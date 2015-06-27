#!/bin/bash -ex

postconf -e virtual_alias_domains="${DOMAINS}"
postconf -e /etc/postfix/virtual="$(echo $MAPPINGS | sed 's/, */\n/g')"
postmap /etc/postfix/virtual
service postfix restart
sleep infinity

