Docker Image With Postfix Configuration For Mail Forwarding
===========================================================

Do you own several domains? Do you want to simply forward mails to
your domains to another mail account? Then you found the solution!

This docker image just forwards all mails to predefined aliases to
other accounts.

In `MAPPINGS`, you can define a semicolon separated list of virtual aliases.

Optionally you can specify your mail servers full qualified host name
in `MAILHOST`. By default, it is set to the first vitual alias domain
in `MAPPINGS`.

Example given:

You own `example.com` and `example.net` and you want to setup these
two domains to receive mails for `info@example.com` and
`info@example.net`, and forward these mails to the corresponding
account in your company `info@mycompany.com`.

    docker run -d --restart unless-stopped --name mailforward \
               -p 25:25 \
               -e 'MAPPINGS=info@example.com info@mycompany.com; info@example.net info@mycompany.com' \
               mwaeckerlin/mailforward
              
Mail host name is set to `example.com`, because `info@example.com` is
the first virtual alias and `MAILHOST` is not set.

Of course, you must setup DNS to specify the host where this container
runs as mail `MX` record for the domains you want to receive
mails. For this task, I use
[mwaeckerlin/bind](https://hub.docker.com/r/mwaeckerlin/bind).

That's all. Everything else (i.e. the `virtual_alias_domains`) is
setup from this information. The image already does a decent SPAM
prevention.


TLS
---

Run a letsencrypt client, e.g. the one that comes with
[mwaeckerlin/reverse-proxy](https://hub.docker.com/r/mwaeckerlin/reverse-proxy),
to get the certificates. Then simply mount `/etc/letsencrypt` into
`/etc/letsencrypt`. If there are certificates for the maildomain, TLS
is configured.

The requires files are, e.g. for domain `example.com`:
 - `/etc/letsencrypt/live/example.com/fullchain.pem`
 - `/etc/letsencrypt/live/example.com/privkey.pem`


Greylisting
-----------

There is a SPAM prevention algorithmus named
[greylisting](https://wikipedia.org/wiki/Greylisting), which means
that any new sender of emails is blocked for some times. Only if the
sender retries the mail is delivered. The advantage of this mechanism
is, that most spammers only try to send an email once, while correctly
implemented mailers must retry. So a lot of spam never reaches your
mailbox.

To enable greylisting, run a separate greylisting container, using
e.g. [mwaeckerlin/postgrey](https://hub.docker.com/r/mwaeckerlin/postgrey/),
then either link it to this container or use teh environment variable
`GREYLIST` to specify the greylisting container's url and port:

   docker run -d --restart unless-stopped --name postgrey \
              mwaeckerlin/postgrey
   docker run -d --restart unless-stopped --name mailforward \
              -p 25:25 \
              -e 'MAPPINGS=…' \
              --link postgrey:postgrey \
              mwaeckerlin/mailforward

Alternatively, e.g. for docker swarm, specify a yaml file:

```
version: '3.3'
services:
  postgrey:
    image: mwaeckerlin/postgrey
    ports:
      - 10023:10023
  mailforward:
    image: mwaeckerlin/mailforward
    ports:
      - 25:25
    volumes:
      - type: bind
        source: /srv/volumes/reverse-proxy/letsencrypt
        target: /etc/letsencrypt
    environment:
      - 'GREYLIST=postgrey:10023'
      - 'MAPPINGS=…'
```
