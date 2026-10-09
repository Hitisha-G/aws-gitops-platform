#!/usr/bin/env bash
# Guardrail checks for VPC Flow Logs CloudWatch retention days.
# AWS PutRetentionPolicy accepts a fixed set of day values; the module
# validation, root default, tfvars example, and log group wiring must agree.
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

# Print the default numeric (or unquoted) value of a variable block.
default_of() {
  variable_block "$1" "$2" | sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' | tr -d '"'
}

# Known AWS CloudWatch Logs retention-in-days values (PutRetentionPolicy).
# Module may list a subset; every module value must be in this set, and the
# common short/medium horizons must be present.
AWS_SUPPORTED="1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1096,1827,2192,2557,2922,3288,3653"
COMMON_REQUIRED="1,3,5,7,14,30,60,90,180,365,731,1827,3653"

# 1. Module validation lists a non-empty set of AWS-supported retention days.
module_block="$(variable_block "$MODULE_VARS" flow_logs_retention_days)"
allowed="$(printf '%s\n' "$module_block" \
  | sed -n 's/.*contains(\[\(.*\)\],[[:space:]]*var\.flow_logs_retention_days).*/\1/p' \
  | tr -d ' ' | tr ',' '\n' | sort -n | paste -sd, -)"
if [[ -z "$allowed" ]]; then
  fail "module validation does not list a contains([...]) retention set"
else
  pass "module validation lists retention set ($allowed)"
fi

# 2. Every listed value is AWS-supported; required common values are present.
IFS=',' read -r -a allowed_arr <<< "$allowed"
for value in "${allowed_arr[@]}"; do
  if [[ ",$AWS_SUPPORTED," == *",$value,"* ]]; then
    pass "module value $value is AWS-supported"
  else
    fail "module value $value is not an AWS CloudWatch Logs retention day"
  fi
done

IFS=',' read -r -a common_arr <<< "$COMMON_REQUIRED"
for value in "${common_arr[@]}"; do
  if [[ ",$allowed," == *",$value,"* ]]; then
    pass "module includes common retention $value"
  else
    fail "module missing common retention value $value"
  fi
done

# 3. Validation error message mentions CloudWatch / retention so users know why.
if printf '%s\n' "$module_block" | grep -Eqi 'error_message.*(CloudWatch|retention)'; then
  pass "module validation error message mentions CloudWatch/retention"
else
  fail "module validation error message does not mention CloudWatch or retention"
fi

# 4. Defaults stay at 14 in both the module and the root, so they cannot drift.
module_default="$(default_of "$MODULE_VARS" flow_logs_retention_days)"
root_default="$(default_of "$ROOT_VARS" flow_logs_retention_days)"
assert_eq "module default" "14" "$module_default"
assert_eq "root default matches module default" "$module_default" "$root_default"

# 5. Root module forwards the variable instead of hard-coding a value.
if grep -Eq '^[[:space:]]*flow_logs_retention_days[[:space:]]*=[[:space:]]*var\.flow_logs_retention_days' "$ROOT_MAIN"; then
  pass "root module passes flow_logs_retention_days into the VPC module"
else
  fail "root module does not pass var.flow_logs_retention_days into the VPC module"
fi

# 6. The CloudWatch log group reads the variable (no literal retention left behind).
log_group_block="$(awk '/^resource "aws_cloudwatch_log_group" "flow_logs"/ { inside = 1 } inside { print } inside && /^}/ { exit }' "$FLOW_LOGS")"
if printf '%s\n' "$log_group_block" | grep -Eq 'retention_in_days[[:space:]]*=[[:space:]]*var\.flow_logs_retention_days'; then
  pass "aws_cloudwatch_log_group.retention_in_days uses var.flow_logs_retention_days"
else
  fail "aws_cloudwatch_log_group.retention_in_days is not wired to var.flow_logs_retention_days"
fi
if printf '%s\n' "$log_group_block" | grep -Eq 'retention_in_days[[:space:]]*=[[:space:]]*[0-9]'; then
  fail "aws_cloudwatch_log_group still has a hard-coded retention_in_days literal"
else
  pass "aws_cloudwatch_log_group has no hard-coded retention_in_days literal"
fi

# 7. The tfvars example only ever shows a value AWS (and the module) will accept.
example="$(sed -n 's/^[[:space:]]*flow_logs_retention_days[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$TFVARS_EXAMPLE")"
if [[ -n "$example" && ",$allowed," == *",$example,"* ]]; then
  pass "tfvars example uses an allowed value ($example)"
else
  fail "tfvars example flow_logs_retention_days '$example' is not in the module allowed set"
fi

# 8. Near-miss / invalid day counts must not appear in the allowed set.
for candidate in 0 2 13 100 366 1000; do
  if [[ ",$allowed," == *",$candidate,"* ]]; then
    fail "validation would accept invalid value '$candidate'"
  else
    pass "validation rejects '$candidate'"
  fi
done

echo "---"
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
