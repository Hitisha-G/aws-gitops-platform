#!/usr/bin/env bash
# Guardrail checks for the configurable VPC Flow Logs traffic type.
# AWS accepts exactly ACCEPT, REJECT, or ALL for aws_flow_log.traffic_type,
# so the module validation, root default, tfvars example, and resource wiring
# must all agree. Values are case-sensitive ("all" is rejected by AWS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_VARS="$ROOT/terraform/modules/vpc/variables.tf"
ROOT_VARS="$ROOT/terraform/variables.tf"
ROOT_MAIN="$ROOT/terraform/main.tf"
FLOW_LOGS="$ROOT/terraform/modules/vpc/flow_logs.tf"
TFVARS_EXAMPLE="$ROOT/terraform/terraform.tfvars.example"
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

# Print the default string value of a variable block.
default_of() {
  variable_block "$1" "$2" | sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p'
}

AWS_ALLOWED="ACCEPT,ALL,REJECT"

# 1. Module validation lists exactly the AWS-supported values (no more, no less).
module_block="$(variable_block "$MODULE_VARS" flow_logs_traffic_type)"
allowed="$(printf '%s\n' "$module_block" \
  | sed -n 's/.*contains(\[\(.*\)\],[[:space:]]*var\.flow_logs_traffic_type).*/\1/p' \
  | tr -d ' "' | tr ',' '\n' | sort | paste -sd, -)"
assert_eq "module validation allowed set" "$AWS_ALLOWED" "$allowed"

# 2. Validation error message names every allowed value so users can fix input.
if printf '%s\n' "$module_block" | grep -q 'error_message.*ACCEPT.*REJECT.*ALL'; then
  pass "module validation error message lists ACCEPT, REJECT, and ALL"
else
  fail "module validation error message does not list all allowed values"
fi

# 3. Defaults stay at ALL in both the module and the root, so they cannot drift.
module_default="$(default_of "$MODULE_VARS" flow_logs_traffic_type)"
root_default="$(default_of "$ROOT_VARS" flow_logs_traffic_type)"
assert_eq "module default" "ALL" "$module_default"
assert_eq "root default matches module default" "$module_default" "$root_default"

# 4. Root module forwards the variable instead of hard-coding a value.
if grep -Eq '^[[:space:]]*flow_logs_traffic_type[[:space:]]*=[[:space:]]*var\.flow_logs_traffic_type' "$ROOT_MAIN"; then
  pass "root module passes flow_logs_traffic_type into the VPC module"
else
  fail "root module does not pass var.flow_logs_traffic_type into the VPC module"
fi

# 5. The aws_flow_log resource reads the variable (no literal traffic_type left behind).
flow_log_block="$(awk '/^resource "aws_flow_log" "this"/ { inside = 1 } inside { print } inside && /^}/ { exit }' "$FLOW_LOGS")"
if printf '%s\n' "$flow_log_block" | grep -Eq 'traffic_type[[:space:]]*=[[:space:]]*var\.flow_logs_traffic_type'; then
  pass "aws_flow_log.traffic_type uses var.flow_logs_traffic_type"
else
  fail "aws_flow_log.traffic_type is not wired to var.flow_logs_traffic_type"
fi
if printf '%s\n' "$flow_log_block" | grep -Eq 'traffic_type[[:space:]]*=[[:space:]]*"'; then
  fail "aws_flow_log still has a hard-coded traffic_type literal"
else
  pass "aws_flow_log has no hard-coded traffic_type literal"
fi

# 6. The tfvars example only ever shows a value AWS will accept.
example="$(sed -n 's/^[[:space:]]*flow_logs_traffic_type[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS_EXAMPLE")"
if [[ -n "$example" && ",$AWS_ALLOWED," == *",$example,"* ]]; then
  pass "tfvars example uses an allowed value ($example)"
else
  fail "tfvars example flow_logs_traffic_type '$example' is not one of $AWS_ALLOWED"
fi

# 7. Case sensitivity: Terraform contains() is exact, so near-miss inputs must be rejected.
for candidate in all Accept reject " ALL" NONE; do
  if [[ ",$allowed," == *",$candidate,"* ]]; then
    fail "validation would accept invalid value '$candidate'"
  else
    pass "validation rejects '$candidate'"
  fi
done

echo "---"
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
