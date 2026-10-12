# shellcheck shell=bash
# Shared helpers for the shell unit checks under tests/.
# Source from a test script after setting `set -euo pipefail`:
#   # shellcheck source=lib/assert.sh
#   source "$(dirname "$0")/lib/assert.sh"
# Each test keeps its own PASS/FAIL tally and ends with `finish`.

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label ($actual)"
  else
    fail "$label expected=$expected actual=$actual"
  fi
}

# Print the body of `variable "<name>" { ... }` from a .tf file.
variable_block() {
  local file="$1" name="$2"
  awk -v name="$name" '
    $0 ~ "^variable \"" name "\"" { inside = 1 }
    inside { print }
    inside && /^}/ { exit }
  ' "$file"
}

# Print the pass/fail summary and exit non-zero if any check failed.
finish() {
  echo "---"
  echo "passed=$PASS failed=$FAIL"
  [[ "$FAIL" -eq 0 ]]
}
