#!/usr/bin/env bash
# Contract checks for optional VPC endpoints.
# Keeps root toggles, module variables, gateway/interface wiring, the shared
# regional service-name prefix, and the ECR→S3 precondition aligned so a
# private ECR pull cannot be enabled without the S3 gateway layers need.
# Also owns interface endpoint wiring (shared SG, private DNS) and outputs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$(dirname "$0")/lib/assert.sh"
MODULE_VARS="$ROOT/terraform/modules/vpc/variables.tf"
ROOT_VARS="$ROOT/terraform/variables.tf"
ROOT_MAIN="$ROOT/terraform/main.tf"
ENDPOINTS="$ROOT/terraform/modules/vpc/endpoints.tf"
MODULE_OUTPUTS="$ROOT/terraform/modules/vpc/outputs.tf"
TFVARS_EXAMPLE="$ROOT/terraform/terraform.tfvars.example"

default_of() {
  variable_block "$1" "$2" | sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' | tr -d '"'
}

# name:expected_default pairs (gateway on, interface off).
ENDPOINT_SPECS=(
  "enable_s3_endpoint:true"
  "enable_dynamodb_endpoint:true"
  "enable_ssm_endpoint:false"
  "enable_ecr_endpoint:false"
  "enable_logs_endpoint:false"
  "enable_secretsmanager_endpoint:false"
  "enable_kms_endpoint:false"
)

# 1. Every toggle exists on both root and module with matching defaults.
for spec in "${ENDPOINT_SPECS[@]}"; do
  name="${spec%%:*}"
  expected="${spec##*:}"
  if grep -q "variable \"$name\"" "$MODULE_VARS" && grep -q "variable \"$name\"" "$ROOT_VARS"; then
    pass "root and module declare $name"
  else
    fail "missing $name on root or module variables"
  fi
  module_default="$(default_of "$MODULE_VARS" "$name")"
  root_default="$(default_of "$ROOT_VARS" "$name")"
  assert_eq "module $name default" "$expected" "$module_default"
  assert_eq "root $name default matches module" "$module_default" "$root_default"
done

# 2. Root forwards each toggle into the VPC module (no hard-coded true/false).
for spec in "${ENDPOINT_SPECS[@]}"; do
  name="${spec%%:*}"
  if grep -Eq "^[[:space:]]*${name}[[:space:]]*=[[:space:]]*var\\.${name}" "$ROOT_MAIN"; then
    pass "root passes $name into VPC module"
  else
    fail "root does not pass var.$name into VPC module"
  fi
done

# 3. Shared regional service-name prefix used by gateway and interface endpoints.
# Use grep -F + escaped ${...} so ShellCheck SC2016 stays quiet (same pattern as
# the EKS cluster tag check in tests/eks_subnet_tags_test.sh).
if grep -q 'endpoint_service_prefix' "$ENDPOINTS" \
  && grep -qF "com.amazonaws.\${data.aws_region.current.name}" "$ENDPOINTS"; then
  pass "endpoints.tf defines regional endpoint_service_prefix"
else
  fail "endpoints.tf missing endpoint_service_prefix local"
fi
if grep -qF "\${local.endpoint_service_prefix}.s3" "$ENDPOINTS" \
  && grep -qF "\${local.endpoint_service_prefix}.dynamodb" "$ENDPOINTS"; then
  pass "gateway endpoints use local.endpoint_service_prefix"
else
  fail "gateway S3/DynamoDB service_name not using endpoint_service_prefix"
fi
if grep -qF "\${local.endpoint_service_prefix}.\${each.value}" "$ENDPOINTS"; then
  pass "interface endpoints use local.endpoint_service_prefix"
else
  fail "interface endpoint service_name not using endpoint_service_prefix"
fi

# 4. Gateway endpoints are count-gated and attach to the private route table.
for ep in s3 dynamodb; do
  block="$(awk -v name="$ep" '
    $0 ~ "^resource \"aws_vpc_endpoint\" \"" name "\"" { inside = 1 }
    inside { print }
    inside && /^}/ { exit }
  ' "$ENDPOINTS")"
  flag="enable_${ep}_endpoint"
  if printf '%s\n' "$block" | grep -Eq "count[[:space:]]*=[[:space:]]*var\\.${flag} \\? 1 : 0" \
    && printf '%s\n' "$block" | grep -q 'vpc_endpoint_type.*=.*"Gateway"' \
    && printf '%s\n' "$block" | grep -q 'route_table_ids.*=.*\[aws_route_table.private.id\]'; then
    pass "$ep gateway endpoint is count-gated on private RT"
  else
    fail "$ep gateway endpoint missing count gate, Gateway type, or private RT"
  fi
done

# 5. Interface map is gated by each interface toggle and lists expected services.
if grep -q 'var.enable_ssm_endpoint' "$ENDPOINTS" \
  && grep -q 'ssm.*=.*"ssm"' "$ENDPOINTS" \
  && grep -q 'ssmmessages.*=.*"ssmmessages"' "$ENDPOINTS" \
  && grep -q 'ec2messages.*=.*"ec2messages"' "$ENDPOINTS"; then
  pass "SSM interface trio gated by enable_ssm_endpoint"
else
  fail "SSM interface services missing or not gated"
fi
if grep -q 'var.enable_ecr_endpoint' "$ENDPOINTS" \
  && grep -q 'ecr_api.*=.*"ecr.api"' "$ENDPOINTS" \
  && grep -q 'ecr_dkr.*=.*"ecr.dkr"' "$ENDPOINTS"; then
  pass "ECR api/dkr interface pair gated by enable_ecr_endpoint"
else
  fail "ECR interface services missing or not gated"
fi
for pair in 'enable_logs_endpoint:logs' 'enable_secretsmanager_endpoint:secretsmanager' 'enable_kms_endpoint:kms'; do
  flag="${pair%%:*}"
  svc="${pair##*:}"
  if grep -q "var.${flag}" "$ENDPOINTS" && grep -Eq "${svc}[[:space:]]*=[[:space:]]*\"${svc}\"" "$ENDPOINTS"; then
    pass "$svc interface endpoint gated by $flag"
  else
    fail "$svc interface endpoint missing or not gated by $flag"
  fi
done

# 6. ECR private pulls require the S3 gateway (image layers live in S3).
if grep -Eq 'condition[[:space:]]*=[[:space:]]*!var\.enable_ecr_endpoint \|\| var\.enable_s3_endpoint' "$ENDPOINTS"; then
  pass "precondition requires enable_s3_endpoint when enable_ecr_endpoint is true"
else
  fail "missing ECR→S3 precondition on interface endpoint security group"
fi
if grep -q 'enable_ecr_endpoint requires enable_s3_endpoint' "$ENDPOINTS"; then
  pass "ECR→S3 precondition error message names both flags"
else
  fail "ECR→S3 precondition error message does not name both flags"
fi

# 7. tfvars example documents the toggles without inventing unknown names.
for spec in "${ENDPOINT_SPECS[@]}"; do
  name="${spec%%:*}"
  if grep -Eq "^[[:space:]]*${name}[[:space:]]*=" "$TFVARS_EXAMPLE"; then
    pass "tfvars example documents $name"
  else
    fail "tfvars example missing $name"
  fi
done

# 8. One shared interface resource: for_each over the service map, private DNS,
#    AZ-ordered private subnets, and the shared endpoint security group.
iface_block="$(awk '
  /^resource "aws_vpc_endpoint" "interface"/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$ENDPOINTS")"
if printf '%s\n' "$iface_block" | grep -q 'for_each = local.interface_endpoint_services' \
  && printf '%s\n' "$iface_block" | grep -q 'vpc_endpoint_type.*=.*"Interface"'; then
  pass "interface endpoints use for_each over interface_endpoint_services"
else
  fail "interface endpoints not consolidated via for_each"
fi
if printf '%s\n' "$iface_block" | grep -q 'private_dns_enabled.*=.*true' \
  && printf '%s\n' "$iface_block" | grep -q 'subnet_ids.*=.*local.private_subnet_ids' \
  && printf '%s\n' "$iface_block" | grep -q 'security_group_ids.*=.*\[aws_security_group.vpc_endpoints\[0\].id\]'; then
  pass "interface endpoints use private DNS, private subnets, and endpoint SG"
else
  fail "interface endpoints missing private DNS / private subnet / SG wiring"
fi
if grep -q 'private_subnet_ids = \[' "$ENDPOINTS" \
  && grep -q 'aws_subnet.private\[az\].id' "$ENDPOINTS"; then
  pass "private_subnet_ids local derived from AZ-ordered private subnets"
else
  fail "missing private_subnet_ids local for interface endpoints"
fi

# 9. Endpoint SG exists only when an interface service is on, and only allows
#    HTTPS to and from the VPC CIDR.
sg_block="$(awk '
  /^resource "aws_security_group" "vpc_endpoints"/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$ENDPOINTS")"
if printf '%s\n' "$sg_block" | grep -q 'count = length(local.interface_endpoint_services) > 0 ? 1 : 0'; then
  pass "endpoint SG count gates on interface_endpoint_services"
else
  fail "endpoint SG count missing interface_endpoint_services gate"
fi
if printf '%s\n' "$sg_block" | grep -q 'from_port.*=.*443' \
  && printf '%s\n' "$sg_block" | grep -q 'to_port.*=.*443' \
  && printf '%s\n' "$sg_block" | grep -q 'cidr_blocks.*=.*\[var.vpc_cidr\]'; then
  pass "endpoint SG restricts HTTPS to the VPC CIDR"
else
  fail "endpoint SG missing HTTPS-from-VPC CIDR restriction"
fi

# 10. Each interface output reads its own map key behind the matching toggle.
for pair in 'ssm:enable_ssm_endpoint' 'ssmmessages:enable_ssm_endpoint' \
  'ec2messages:enable_ssm_endpoint' 'ecr_api:enable_ecr_endpoint' \
  'ecr_dkr:enable_ecr_endpoint' 'logs:enable_logs_endpoint' \
  'secretsmanager:enable_secretsmanager_endpoint' 'kms:enable_kms_endpoint'; do
  key="${pair%%:*}"
  flag="${pair##*:}"
  if grep -A3 "^output \"${key}_endpoint_id\"" "$MODULE_OUTPUTS" \
    | grep -qF "var.${flag} ? aws_vpc_endpoint.interface[\"${key}\"].id : null"; then
    pass "${key}_endpoint_id output reads interface[\"${key}\"] behind $flag"
  else
    fail "${key}_endpoint_id output missing or not gated by $flag"
  fi
done

finish
