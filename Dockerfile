FROM mwaeckerlin/ubuntu-base
MAINTAINER mwaeckerlin
ENV TERM xterm

# setup domains as in the following example:
ENV MAILHOST mail.example.com
ENV DOMAINS ""
ENV MAPPINGS ""

EXPOSE 25 587

VOLUME /var/spool/mail/

# Preselections for installation 
RUN echo mail > /etc/hostname
RUN echo "postfix postfix/mailname string your.hostname.com" | debconf-set-selections
RUN echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
RUN apt-get update
RUN apt-get install -y postfix

# Configure
RUN postconf -e smtpd_banner="\$myhostname ESMTP" && \
    postconf -e mail_spool_directory="/var/spool/mail/" && \
    postconf -e mailbox_command=""

WORKDIR /

ADD start.sh /start.sh

WORKDIR /var/spool/mail/
    
CMD /start.sh
