Docker Image With Postfix Configuration For Mail Forwarding
===========================================================

Do you own several domains? Do you want to simply forward mails to
your domains to another mail account? Then you found the solution!

This docker image just forwards all mails to predefined aliases to
other accounts.

In `MAPPINGS`, you can define a comma separated list of virtual aliases.

Optionally you can specify your mail servers full qualified host name
in `MAILHOST`. By default, it is set to the first vitual alias domain
in `MAPPINGS`.

Example given:

You own `example.com` and `example.net` and you want to setup these
two domains to receive mails for `info@example.com` and
`info@example.net`, and forward these mails to the corresponding
account in your company `info@mycompany.com`.

     -d --restart unless-stopped --name mailforward \
               -p 587:587 -p 25:25 \
               -e 'MAPPINGS=info@example.com info@mycompany.com, info@example.net info@mycompany.com' \
               mwaeckerlin/mailforward
              
Mail host name is set to `example.com`, because `info@example.com` is
the first virtual alias and `MAILHOST` is not set.

Of course, you must setup DNS to specify the host where this container
runs as mail `MX` record for the domains you want to receive mails.

That's all. Everything else (i.e. the `virtual_alias_domains`) is
setup from this information. The image already does a decent SPAM
prevention.
