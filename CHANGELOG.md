# Changelog

- 2026-10-23 **2.0.1**
    - The version line 2 is built and published again as `mwaeckerlin/mailforward:2`, for amd64 and arm64, on every push to this branch and every week with the run on master, so it gets the security fixes of its base images
    - Forwarding works again on current Alpine: Alpine builds postfix without Berkeley DB, so the `hash:` map type no longer exists and every alias recipient drew a temporary failure; the alias map now uses the default map type of the installed postfix
    - A test checks the image: postfix accepts its configuration, the mail system starts, every address of `MAPPINGS` is forwarded to its target, and the `GREYLIST` milter reaches the effective configuration
