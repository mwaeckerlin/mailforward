FROM mwaeckerlin/smtp-relay as build
#RUN echo mail > /etc/hostname 
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
# SPAM Prevention 
RUN postconf -e smtpd_hard_error_limit='1' 
RUN postconf -e smtpd_helo_required='yes' 
RUN postconf -e smtpd_helo_restrictions='permit_sasl_authenticated, reject_invalid_hostname, reject_non_fqdn_hostname, reject_unauth_pipelining' 
RUN postconf -e smtpd_sender_restrictions='permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_sender, reject_unauth_pipelining' 
RUN postconf -e smtpd_recipient_restrictions='permit_sasl_authenticated, permit_mynetworks, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org' 
RUN postconf -e smtpd_client_restrictions='reject_invalid_hostname, reject_rhsbl_sender dbl.spamhaus.org, reject_rhsbl_client dbl.spamhaus.org, reject_rhsbl_helo dbl.spamhaus.org' 
RUN postconf -e strict_rfc821_envelopes='yes' 
RUN postconf -e smtpd_relay_restrictions='permit_sasl_authenticated, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org'
#, check_policy_service inet:127.0.0.1:10023'
COPY start.sh /start.sh

FROM mwaeckerlin/scratch
ENV CONTAINERNAME "mailforward"
ENV MAILHOST      ""
ENV MAPPINGS      ""
ENV LOCAL_DOMAINS ""
ENV GREYLIST      ""
EXPOSE 25
VOLUME /etc/letsencrypt
COPY --from=build / /
USER root
CMD /start.sh
