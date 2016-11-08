FROM ubuntu
MAINTAINER mwaeckerlin

# setup domains as in the following example:
#ENV MAILHOST mail.example.com
ENV DOMAINS ""
ENV MAPPINGS ""

EXPOSE 25 587

VOLUME ["/var/spool/mail/"]

WORKDIR /tmp

# Preselections for installation 
RUN echo mail > /etc/hostname; \
    echo "postfix postfix/main_mailer_type string Internet site" >> preseed.txt; \
    echo "postfix postfix/mailname string mail.example.com" >> preseed.txt; \
    debconf-set-selections preseed.txt && rm preseed.txt

# Install packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends postfix && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* preseed.txt

# Configure
RUN postconf -e smtpd_banner="\$myhostname ESMTP" && \
    postconf -e mail_spool_directory="/var/spool/mail/" && \
    postconf -e mailbox_command=""

WORKDIR /

ADD start.sh /start.sh

WORKDIR /var/spool/mail/
    
CMD ["/start.sh"]
