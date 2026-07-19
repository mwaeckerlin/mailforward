#!/usr/bin/env bash
# Config validation: init must refuse malformed environment values.
#
# MAPPINGS is written into the virtual(5) map file and every other env
# knob is fed to `postconf -e`. A value containing a newline would
# smuggle arbitrary extra directives into those files (config
# injection); a non-numeric limit would render an invalid main.cf.
# init therefore whitelist-validates every value up front and exits
# with a clear `invalid <VAR>` error before anything else runs.
#
# The image is shell-free, so the checks run from outside: the
# `--healthcheck` entrypoint path performs the same validation first,
# fails fast (no daemon is running) and never touches the network —
# `--network none` pins that. `--pull=never` keeps docker from testing
# a stale registry image instead of the local build.
#
# Usage: tests/config-validation.sh IMAGE

set -uo pipefail

IMAGE="${1:-mwaeckerlin/mailforward}"

PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

_image_exists() {
    if docker image inspect "${IMAGE}" > /dev/null 2>&1; then
        return 0
    fi
    _fail "image_exists" "image not built — run 'npm run build' first"
    return 1
}

# A malformed value must abort with a message naming the variable.
_reject() {
    local name="$1" var="$2" value="$3"
    local out rc
    out=$(timeout 30 docker run --rm --pull=never --network none \
              -e "${var}=${value}" "${IMAGE}" --healthcheck 2>&1)
    rc=$?
    if [[ ${rc} -ne 0 && "${out}" == *"invalid ${var}"* ]]; then
        _pass "reject_${name}"
    else
        _fail "reject_${name}" "value not rejected (rc=${rc}): ${out}"
    fi
}

# A well-formed value must pass validation (the probe itself fails —
# no daemon is running — but no validation error may appear).
_accept() {
    local name="$1"
    shift
    local out
    out=$(timeout 30 docker run --rm --pull=never --network none \
              "$@" "${IMAGE}" --healthcheck 2>&1)
    if [[ "${out}" == *"invalid "* ]]; then
        _fail "accept_${name}" "valid value rejected: ${out}"
    else
        _pass "accept_${name}"
    fi
}

echo "==> Config validation: malformed environment must be refused"

_image_exists || { echo ""; echo "==> Config validation results: 0 passed, 1 failed"; exit 1; }

_reject mappings_injection    MAPPINGS      $'a@b.c d@e.f\nevil@x.y catchall@z.z'
_reject local_domains_bad     LOCAL_DOMAINS $'example.com\nmynetworks = 0.0.0.0/0'
_reject mailhost_bad          MAILHOST      "mail.example.com bad"
_reject greylist_injection    GREYLIST      $'postgrey:10025\nmynetworks = 0.0.0.0/0'
_reject size_not_numeric      MESSAGE_SIZE_LIMIT    "100G"
_reject hard_error_bad        SMTP_HARD_ERROR_LIMIT "many"

_accept defaults
_accept explicit_values \
    -e MAPPINGS='forward@fwd.local sink@extern.local; info@fwd.local admin+mail@extern.local' \
    -e LOCAL_DOMAINS='fwd.local other.local' \
    -e MAILHOST=fwd.local \
    -e GREYLIST=postgrey:10025 \
    -e MESSAGE_SIZE_LIMIT=107374182400 \
    -e SMTP_HARD_ERROR_LIMIT=20

echo ""
echo "==> Config validation results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed checks: ${FAILED_NAMES[*]}"
    exit 1
fi
