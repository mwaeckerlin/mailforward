#!/usr/bin/env bash
# Environment contract: every operator setting reaches the effective
# postfix configuration — the image default when the variable is unset,
# the operator's value when it is set.
#
# Each case starts the image with its environment, waits until init has
# configured postfix and the master listens (the --healthcheck probe
# answers), and reads the effective value with `postconf -h` inside the
# running container. `--network none` keeps the container off every
# network; `--pull=never` tests the local build. MAILHOST is set in every
# case so postfix has a host name to start with.
#
# Usage: tests/env-config.sh IMAGE

set -uo pipefail

IMAGE="${1:-mwaeckerlin/mailforward}"

PASS=0
FAIL=0
declare -a FAILED_NAMES
declare -a CONTAINERS

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

_cleanup() {
    [[ ${#CONTAINERS[@]} -gt 0 ]] && docker rm -f "${CONTAINERS[@]}" > /dev/null 2>&1
}
trap _cleanup EXIT

_image_exists() {
    if docker image inspect "${IMAGE}" > /dev/null 2>&1; then
        return 0
    fi
    _fail "image_exists" "image not built — run 'npm run build' first"
    return 1
}

# Start the image with the given docker arguments; sets CID once init is
# done and the SMTP listener answers, fails after 60 probes.
_start() {
    local name="$1" i
    shift
    CID=$(docker run -d --pull=never --network none -e MAILHOST=fwd.local "$@" "${IMAGE}")
    CONTAINERS+=("${CID}")
    for i in $(seq 1 60); do
        if docker exec "${CID}" /usr/bin/init --healthcheck > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    _fail "${name}_started" "listener never came up: $(docker logs "${CID}" 2>&1)"
    return 1
}

_expect() {
    local name="$1" param="$2" want="$3" got
    got=$(docker exec "${CID}" /usr/sbin/postconf -h "${param}" 2>/dev/null)
    if [[ "${got}" == "${want}" ]]; then
        _pass "${name}"
    else
        _fail "${name}" "${param} = '${got}', expected '${want}'"
    fi
}

RECIPIENT_BASE="permit_sasl_authenticated, permit_mynetworks, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining"
RELAY_BASE="permit_sasl_authenticated, reject_unknown_recipient_domain, reject_non_fqdn_recipient, reject_unauth_destination, reject_unauth_pipelining"

echo "==> Environment contract: settings reach the effective configuration"

_image_exists || { echo ""; echo "==> Environment contract results: 0 passed, 1 failed"; exit 1; }

if _start defaults; then
    _expect default_dnsbl_recipient smtpd_recipient_restrictions \
        "${RECIPIENT_BASE}, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org"
    _expect default_dnsbl_relay smtpd_relay_restrictions \
        "${RELAY_BASE}, reject_rbl_client ix.dnsbl.manitu.net, reject_rbl_client sbl.spamhaus.org, reject_rbl_client xbl.spamhaus.org"
    _expect default_rhsbl_client smtpd_client_restrictions \
        "reject_invalid_hostname, reject_rhsbl_sender dbl.spamhaus.org, reject_rhsbl_client dbl.spamhaus.org, reject_rhsbl_helo dbl.spamhaus.org"
    _expect default_mynetworks mynetworks "127.0.0.1/32 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8"
    _expect default_relayhost  relayhost  ""
fi

if _start override \
       -e DNSBL_SERVERS="bl.example.org zen.example.org" \
       -e RHSBL_SERVERS=dbl.example.org \
       -e MYNETWORKS="10.1.0.0/16, 127.0.0.0/8" \
       -e RELAYHOST=relay.example.com:587; then
    _expect override_dnsbl_recipient smtpd_recipient_restrictions \
        "${RECIPIENT_BASE}, reject_rbl_client bl.example.org, reject_rbl_client zen.example.org"
    _expect override_dnsbl_relay smtpd_relay_restrictions \
        "${RELAY_BASE}, reject_rbl_client bl.example.org, reject_rbl_client zen.example.org"
    _expect override_rhsbl_client smtpd_client_restrictions \
        "reject_invalid_hostname, reject_rhsbl_sender dbl.example.org, reject_rhsbl_client dbl.example.org, reject_rhsbl_helo dbl.example.org"
    _expect override_mynetworks mynetworks "10.1.0.0/16, 127.0.0.0/8"
    _expect override_relayhost  relayhost  "[relay.example.com]:587"
fi

if _start disable_dnsbl_wins -e DISABLE_DNSBL=1 -e DNSBL_SERVERS=bl.example.org; then
    _expect disable_dnsbl_wins smtpd_recipient_restrictions "${RECIPIENT_BASE}"
fi

echo ""
echo "==> Environment contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed checks: ${FAILED_NAMES[*]}"
    exit 1
fi
