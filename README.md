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
               -v mailforward-spool:/var/spool/postfix \
               -e 'MAPPINGS=info@example.com info@mycompany.com; info@example.net info@mycompany.com' \
               mwaeckerlin/mailforward

The named `mailforward-spool` volume keeps the mail queue: postfix
answers `250 Ok` as soon as a mail is safely queued — the sender never
retries after that — and a deferred forward can sit in the queue for
hours. Without the volume, a container recreate or image update
silently destroys accepted-but-unforwarded mail.
              
Mail host name is set to `example.com`, because `info@example.com` is
the first virtual alias and `MAILHOST` is not set.

Of course, you must setup DNS to specify the host where this container
runs as mail `MX` record for the domains you want to receive
mails. For this task, I use
[mwaeckerlin/bind](https://hub.docker.com/r/mwaeckerlin/bind).

That's all. Everything else (i.e. the `virtual_alias_domains`) is
setup from this information. The image already does a decent SPAM
prevention.


Headless image
--------------

The image is headless: a small compiled `init` binary configures
postfix from the environment and execs the postfix `master` daemon in
container mode — no shell, no busybox, no package manager in the
shipped image. `init --healthcheck` TCP-probes the SMTP listener on
127.0.0.1:25 and can be wired as a Docker healthcheck:

```yaml
healthcheck:
  test: ["CMD", "/usr/bin/init", "--healthcheck"]
```

Trade-off: the container starts as root — the postfix master needs it
to bind port 25 and manage the mail queue — and every postfix service
then drops privileges to the unprivileged `postfix` user per master.cf.


DNS blocklists
--------------

The smtpd restrictions include DNSBL/RHSBL lookups (manitu, spamhaus).
Set **`DISABLE_DNSBL`** to any non-empty value to strip them — for
test or offline stacks whose resolver cannot answer the blocklist
zones (each lookup would stall the SMTP dialogue until the resolver
timeout). Trade-off: without the blocklists, known-bad senders are no
longer rejected at connect time; leave it unset in production.


Delivery-affecting limits
-------------------------

Both limits are deliberately high by default and configurable — a
legitimate mail must never bounce because of an artificial default:

- **`MESSAGE_SIZE_LIMIT`** (bytes, default `107374182400` = 100 GiB,
  `0` = unlimited): maximum accepted message size;
  `mailbox_size_limit` is pinned to the same value.
- **`SMTP_HARD_ERROR_LIMIT`** (default `20`, the postfix standard):
  hard SMTP protocol errors per session before the connection is
  dropped. The image previously hardcoded `1`, which turned a single
  rejected recipient into an abrupt disconnect for the sending server.


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

The protocol floor is TLS 1.2 (1.0/1.1 are broken); STARTTLS stays
opportunistic, so a legacy sender without TLS 1.2 falls back to
plaintext and the mail still arrives — delivery before filtering.


Input validation
----------------

Every environment value is whitelist-validated at start-up before it
is rendered into the virtual alias map or fed to `postconf` — a
malformed value (embedded newline, stray metacharacters, out-of-range
number) aborts the start with a clear `invalid <VAR>` error instead of
rendering a broken or unsafe configuration. Pinned by
`tests/config-validation.sh` (`npm test`).


Greylisting
-----------

There is a SPAM prevention algorithmus named
[greylisting](https://wikipedia.org/wiki/Greylisting), which means
that any new sender of emails is blocked for some times. Only if the
sender retries the mail is delivered. The advantage of this mechanism
is, that most spammers only try to send an email once, while correctly
implemented mailers must retry. So a lot of spam never reaches your
mailbox.

To enable greylisting, run a separate greylisting milter and use the
environment variable `GREYLIST` to specify its host name and optional
port (default 10025). The historical companion image
[mwaeckerlin/postgrey](https://hub.docker.com/r/mwaeckerlin/postgrey/)
(milter-greylist on port 10025) is **deprecated and unmaintained** —
it stays on Docker Hub for existing setups, but for maintained,
score-based greylisting use the full
[mwaeckerlin/mailservice](https://github.com/mwaeckerlin/mailservice)
stack (rspamd) instead:

```yaml
services:
  postgrey:
    image: mwaeckerlin/postgrey
    # no published ports: the milter is only for mailforward — reach it
    # over the shared compose network, never from the host or beyond
  mailforward:
    image: mwaeckerlin/mailforward
    ports:
      - 25:25
    volumes:
      # production persistence bind-mount onto shared storage
      - type: bind
        source: /srv/volumes/reverse-proxy/letsencrypt
        target: /etc/letsencrypt
    environment:
      - 'GREYLIST=postgrey'
      - 'MAPPINGS=…'
```


Related Mail Servers
--------------------

See also:
 - [mwaeckerlin/smtp-relay](https://hub.docker.com/r/mwaeckerlin/smtp-relay) for a simple open mail relay
 - [mwaeckerlin/smtp-relay-tls](https://hub.docker.com/r/mwaeckerlin/smtp-relay-tls) for a simple open mail relay with tls
 - [mwaeckerlin/mailforward](https://hub.docker.com/r/mwaeckerlin/mailforward) for a simple mail forwarder without own inbox
 - [mwaeckerlin/postfix](https://hub.docker.com/r/mwaeckerlin/postfix) for a full featured postfix server
