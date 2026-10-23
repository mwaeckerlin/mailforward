#!/usr/bin/env bash
# Image contract: `postfix check` accepts the configuration, the container
# starts the postfix master, the virtual alias map built from MAPPINGS
# answers a lookup with the forward target, and the GREYLIST milter reaches
# the effective configuration.
#
# `--network none` keeps every container off the network; `--pull=never`
# tests the local build.
#
# Usage: tests/image-contract.sh IMAGE

set -uo pipefail

# the last argument, so `npm test -- <image>` measures another image
IMAGE="${!#}"
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

_results() {
    echo ""
    echo "==> Image contract results: ${PASS} passed, ${FAIL} failed"
    if [[ ${FAIL} -gt 0 ]]; then
        echo "==> Failed contracts: ${FAILED_NAMES[*]}"
        exit 1
    fi
}

# sets CID once `postfix status` reports the master running, fails after 60 probes
_start() {
    local name="$1" i
    shift
    CID=$(docker run -d --pull=never --network none "$@" "${IMAGE}")
    CONTAINERS+=("${CID}")
    for i in $(seq 1 60); do
        if docker exec "${CID}" /usr/sbin/postfix status > /dev/null 2>&1; then
            _pass "${name}_started"
            return 0
        fi
        sleep 1
    done
    _fail "${name}_started" "postfix master never came up: $(docker logs "${CID}" 2>&1)"
    return 1
}

# postconf and postmap print the result on stdout and their warnings on stderr
_expect() {
    local name="$1" param="$2" want="$3" got
    got=$(docker exec "${CID}" /usr/sbin/postconf -h "${param}" 2>/dev/null)
    if [[ "${got}" == "${want}" ]]; then
        _pass "${name}"
    else
        _fail "${name}" "${param} = '${got}', expected '${want}' / $(docker exec "${CID}" /usr/sbin/postconf -h "${param}" 2>&1)"
    fi
}

_contains() {
    local name="$1" param="$2" want="$3" got
    got=$(docker exec "${CID}" /usr/sbin/postconf -h "${param}" 2>/dev/null)
    if [[ " ${got//,/ } " == *" ${want} "* ]]; then
        _pass "${name}"
    else
        _fail "${name}" "${param} = '${got}', expected it to contain '${want}' / $(docker exec "${CID}" /usr/sbin/postconf -h "${param}" 2>&1)"
    fi
}

# the map is looked up with the type the configuration names, as smtpd does
_forwards() {
    local name="$1" address="$2" want="$3" map got
    map=$(docker exec "${CID}" /usr/sbin/postconf -h virtual_alias_maps 2>/dev/null)
    got=$(docker exec "${CID}" /usr/sbin/postmap -q "${address}" "${map}" 2>/dev/null)
    if [[ "${got}" == "${want}" ]]; then
        _pass "${name}"
    else
        _fail "${name}" "lookup of ${address} in ${map} gave '${got}', expected '${want}' / $(docker exec "${CID}" /usr/sbin/postmap -q "${address}" "${map}" 2>&1)"
    fi
}

echo "==> Image contract: ${IMAGE}"

if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
    _fail "image_exists" "image not built — run 'npm run build' first"
    _results
fi

if OUT=$(timeout 60 docker run --rm --pull=never --network none --entrypoint /usr/sbin/postfix "${IMAGE}" check 2>&1); then
    _pass "postfix_check"
else
    _fail "postfix_check" "${OUT}"
fi

if _start mappings \
       -e MAILHOST=mail.example.com \
       -e MAPPINGS="forward@example.com sink@example.org; other@example.net sink@example.org"; then
    _expect   myhostname          myhostname mail.example.com
    _contains alias_domain_first  virtual_alias_domains example.com
    _contains alias_domain_second virtual_alias_domains example.net
    _forwards forward_first       forward@example.com sink@example.org
    _forwards forward_second      other@example.net   sink@example.org
    _contains relay_restricted    smtpd_relay_restrictions reject_unauth_destination
    _expect   no_cert_no_tls      smtpd_use_tls no
    _expect   no_greylist         smtpd_milters ""
fi

if _start greylist \
       -e MAILHOST=mail.example.com \
       -e MAPPINGS="forward@example.com sink@example.org" \
       -e GREYLIST=greylist; then
    _expect greylist_default_port smtpd_milters     "inet:greylist:10025"
    _expect greylist_non_smtpd    non_smtpd_milters "inet:greylist:10025"
fi

_results
