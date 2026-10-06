#!/usr/bin/env bash
# Contract checks between root stack outputs and the VPC module outputs.
# Catches renamed or removed module outputs before terraform validate runs,
# and keeps every output documented for consumers reading `terraform output`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_OUTPUTS="$ROOT/terraform/outputs.tf"
MODULE_OUTPUTS="$ROOT/terraform/modules/vpc/outputs.tf"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# Names declared as `output "<name>"` in a file, one per line.
output_names() {
  sed -n 's/^output "\([^"]*\)".*/\1/p' "$1"
}

# Count output blocks vs. description lines inside them.
count_outputs() { grep -c '^output "' "$1"; }
count_described() {
  awk '/^output "/{inside=1; seen=0} inside && /^[[:space:]]+description[[:space:]]*=/{if(!seen){n++; seen=1}} /^}/{inside=0} END{print n+0}' "$1"
}

mapfile -t module_names < <(output_names "$MODULE_OUTPUTS")
mapfile -t root_refs < <(grep -o 'module\.vpc\.[a-z0-9_]*' "$ROOT_OUTPUTS" | sed 's/^module\.vpc\.//' | sort -u)

if [[ "${#root_refs[@]}" -gt 0 ]]; then
  pass "root outputs reference ${#root_refs[@]} VPC module outputs"
else
  fail "root outputs reference no module.vpc values"
fi

# Every module.vpc.<name> used at the root must be declared by the module.
for ref in "${root_refs[@]}"; do
  if printf '%s\n' "${module_names[@]}" | grep -qx "$ref"; then
    pass "module.vpc.$ref is declared in the VPC module"
  else
    fail "module.vpc.$ref is referenced at the root but not declared by the module"
  fi
done

# Root outputs mirror module names one-to-one (no silent renames for consumers).
while IFS= read -r name; do
  if grep -A4 "^output \"$name\"" "$ROOT_OUTPUTS" | grep -q "module\.vpc\.$name\$"; then
    pass "root output $name passes through module.vpc.$name"
  else
    fail "root output $name does not pass through module.vpc.$name"
  fi
done < <(output_names "$ROOT_OUTPUTS")

# No duplicate output names in either file.
for file in "$ROOT_OUTPUTS" "$MODULE_OUTPUTS"; do
  dupes="$(output_names "$file" | sort | uniq -d)"
  if [[ -z "$dupes" ]]; then
    pass "no duplicate outputs in ${file#"$ROOT"/}"
  else
    fail "duplicate outputs in ${file#"$ROOT"/}: $dupes"
  fi
done

# Every output carries a description.
for file in "$ROOT_OUTPUTS" "$MODULE_OUTPUTS"; do
  total="$(count_outputs "$file")"
  described="$(count_described "$file")"
  if [[ "$total" -eq "$described" ]]; then
    pass "all $total outputs described in ${file#"$ROOT"/}"
  else
    fail "${file#"$ROOT"/} has $total outputs but only $described descriptions"
  fi
done

echo "---"
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
