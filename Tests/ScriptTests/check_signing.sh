#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/PadDisplay-signing-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/project/script"
cp "${1:-$ROOT_DIR/script/build_and_run.sh}" "$TEST_DIR/project/script/build_and_run.sh"
export TEST_DIR
PINNED_ID=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
OTHER_ID=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
cat > "$TEST_DIR/mocks.sh" <<'MOCKS'
pgrep() { return 1; }
security() {
  [[ "$TEST_CERT_PRESENT" != yes ]] || echo '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Test"'
  echo '  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Other"'
}
xcrun() { touch "$TEST_DIR/build-started"; return 88; }
MOCKS

check() {
  local label="$1" mode="$2" configured="$3" identity="$4" present="$5" expected="$6"
  rm -f "$TEST_DIR/build-started" "$TEST_DIR/project/script/signing.identity.local"
  if [[ "$configured" == yes ]]; then echo "$PINNED_ID" > "$TEST_DIR/project/script/signing.identity.local"; fi
  local status=0
  (
    export TEST_CERT_PRESENT="$present" BASH_ENV="$TEST_DIR/mocks.sh"
    if [[ "$identity" == unset ]]; then unset SIGN_IDENTITY; else export SIGN_IDENTITY="$identity"; fi
    bash "$TEST_DIR/project/script/build_and_run.sh" "$mode"
  ) > "$TEST_DIR/output.log" 2>&1 || status=$?
  local built=no
  [[ ! -f "$TEST_DIR/build-started" ]] || built=yes
  local expected_build=no
  [[ "$expected" != 88 ]] || expected_build=yes
  if [[ "$status/$built" != "$expected/$expected_build" ]]; then
    cat "$TEST_DIR/output.log"
    echo "FAIL: $label => status=$status built=$built" >&2
    exit 1
  fi
  echo "PASS: $label => status=$status built=$built"
}

check missing-identity --package no unset yes 1
check pinned-identity --package yes unset yes 88
check unavailable-pinned-identity --package yes unset no 1
check no-ad-hoc-production --package yes - yes 1
check explicit-certificate --build no "$OTHER_ID" no 88
check unknown-certificate --build yes CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC yes 1
check preview-main-bundle-requires-identity --preview no unset yes 1
