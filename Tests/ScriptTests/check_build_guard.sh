#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/PadDisplay-script-test.XXXXXX")"
TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/project/script"
cp "${1:-$ROOT_DIR/script/build_and_run.sh}" "$TEST_DIR/project/script/build_and_run.sh"
export TEST_DIR
cat > "$TEST_DIR/mocks.sh" <<'MOCKS'
pgrep() { echo 4242; }
ps() {
  [[ -e "$TEST_DIR/stopped" ]] && return 1
  if [[ "$TEST_APP" == foreign ]]; then
    echo '/Applications/PadDisplay.app/Contents/MacOS/PadDisplay'
  else
    echo "$TEST_DIR/project/dist/PadDisplay.app/Contents/MacOS/PadDisplay"
  fi
}
pkill() { touch "$TEST_DIR/stopped"; }
kill() { touch "$TEST_DIR/stopped"; }
xcrun() { touch "$TEST_DIR/build-started"; return 88; }
MOCKS

check() {
  local app="$1" mode="$2" expected_status="$3" expected_stop="$4" expected_build="$5"
  rm -f "$TEST_DIR/stopped" "$TEST_DIR/build-started"
  local status=0
  TEST_APP="$app" BASH_ENV="$TEST_DIR/mocks.sh" bash "$TEST_DIR/project/script/build_and_run.sh" "$mode" \
    > "$TEST_DIR/output.log" 2>&1 || status=$?
  local stopped=no built=no
  [[ ! -e "$TEST_DIR/stopped" ]] || stopped=yes
  [[ ! -e "$TEST_DIR/build-started" ]] || built=yes
  if [[ "$status/$stopped/$built" != "$expected_status/$expected_stop/$expected_build" ]]; then
    cat "$TEST_DIR/output.log"
    echo "FAIL: $app $mode => status=$status stopped=$stopped built=$built" >&2
    exit 1
  fi
  echo "PASS: $app $mode => status=$status stopped=$stopped built=$built"
}

check foreign --verify 1 no no
check foreign --package 88 no yes
check staged --verify 88 yes yes
check staged --package 1 no no
check foreign --preview 88 no yes
