FROM mwaeckerlin/ubuntu-base
MAINTAINER mwaeckerlin

# setup domains as in the following example:
ENV MAILHOST ""
ENV MAPPINGS ""

EXPOSE 25

# Preselections for installation 
RUN echo mail > /etc/hostname
RUN echo "postfix postfix/mailname string your.hostname.com" | debconf-set-selections
RUN echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
RUN apt-get install -y postfix telnet

# Configure Defaults
RUN postconf -e smtpd_banner="\$myhostname ESMTP"
RUN postconf -e mail_spool_directory="/var/spool/mail"
RUN postconf -e mailbox_command=""
RUN postconf -e compatibility_level=2
RUN postconf -e mydestination="localhost"
RUN postconf -e smtpd_use_tls=no

# SPAM Prevention
RUN postconf -e smtpd_hard_error_limit='1'
RUN postconf -e smtpd_helo_required='yes'
RUN postconf -e smtpd_helo_restrictions='permit_tls_clientcerts, permit_sasl_authenticated, permit_mynetworks, reject_invalid_hostname, reject_non_fqdn_hostname, reject_unauth_pipelining'
RUN postconf -e smtpd_sender_restrictions='permit_mynetworks, permit_tls_clientcerts, permit_sasl_authenticated, reject_non_fqdn_sender, reject_unauth_pipelining'
RUN postconf -e smtpd_recipient_restrictions='permit_tls_clientcerts, permit_sasl_authenticated, permit_mynetworks, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org'
RUN postconf -e smtpd_client_restrictions='reject_invalid_hostname, reject_rhsbl_sender dbl.spamhaus.org, reject_rhsbl_client dbl.spamhaus.org, reject_rhsbl_helo dbl.spamhaus.org'
RUN postconf -e strict_rfc821_envelopes='yes'

# enable access to letsencrypt
RUN usermod -a -G ssl-cert postfix
VOLUME /etc/letsencrypt

# definitions for our children
ONBUILD RUN mv start.sh mailforward.sh
ONBUILD ADD start.sh /start.sh
