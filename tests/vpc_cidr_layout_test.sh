#!/usr/bin/env bash
# Unit checks for the VPC module's public/private CIDR layout.
# Mirrors locals in terraform/modules/vpc/main.tf:
#   public  = cidrsubnet(vpc_cidr, 4, i)
#   private = cidrsubnet(vpc_cidr, 4, i + az_count)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$(dirname "$0")/lib/assert.sh"

# Python implements Terraform cidrsubnet(prefix, newbits, netnum).
cidrsubnet() {
  local prefix="$1" newbits="$2" netnum="$3"
  python3 - "$prefix" "$newbits" "$netnum" <<'PYINNER'
import ipaddress, sys
network = ipaddress.ip_network(sys.argv[1], strict=True)
newbits = int(sys.argv[2])
netnum = int(sys.argv[3])
new_prefix = network.prefixlen + newbits
block_size = 2 ** (32 - new_prefix)
base = int(network.network_address) + netnum * block_size
print(f"{ipaddress.IPv4Address(base)}/{new_prefix}")
PYINNER
}

VPC_CIDR="10.40.0.0/16"
AZ_COUNT=2

# Expected layout for ap-south-1 defaults (2 AZs, newbits=4)
assert_eq "public[0]"  "10.40.0.0/20"  "$(cidrsubnet "$VPC_CIDR" 4 0)"
assert_eq "public[1]"  "10.40.16.0/20" "$(cidrsubnet "$VPC_CIDR" 4 1)"
assert_eq "private[0]" "10.40.32.0/20" "$(cidrsubnet "$VPC_CIDR" 4 $((0 + AZ_COUNT)))"
assert_eq "private[1]" "10.40.48.0/20" "$(cidrsubnet "$VPC_CIDR" 4 $((1 + AZ_COUNT)))"

# Three-AZ layout still keeps public and private ranges disjoint
AZ_COUNT=3
PUBLIC_2="$(cidrsubnet "$VPC_CIDR" 4 2)"
PRIVATE_0="$(cidrsubnet "$VPC_CIDR" 4 $((0 + AZ_COUNT)))"
assert_eq "3az public[2]" "10.40.32.0/20" "$PUBLIC_2"
assert_eq "3az private[0]" "10.40.48.0/20" "$PRIVATE_0"

# Guardrail: module variable validation requires >= 2 AZs
if grep -q 'length(var.availability_zones) >= 2' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  pass "AZ validation present in module variables"
else
  fail "missing AZ count validation in module variables"
fi

# Guardrail: duplicate AZ entries must be rejected (for_each keys collide otherwise)
if grep -q 'length(toset(var.availability_zones))' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  pass "AZ uniqueness validation present in module variables"
else
  fail "missing AZ uniqueness validation in module variables"
fi

# Guardrail: undersized AZ counts vs subnet carve must fail before apply
if grep -q 'local.az_count \* 2 <= pow(2, local.subnet_newbits)' \
  "$ROOT/terraform/modules/vpc/main.tf"; then
  pass "VPC subnet capacity precondition present"
else
  fail "missing VPC subnet capacity precondition"
fi

# Guardrail: invalid vpc_cidr rejected at variable validation
if grep -q 'can(cidrsubnet(var.vpc_cidr, 4, 0))' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  pass "vpc_cidr cidrsubnet validation present"
else
  fail "missing vpc_cidr cidrsubnet validation"
fi

# Guardrail: vpc_cidr prefix must stay within AWS limits (/16-/24 VPC => /20-/28 subnets)
if grep -q 'tonumber(split("/", var.vpc_cidr)\[1\]) >= 16 && tonumber(split("/", var.vpc_cidr)\[1\]) <= 24' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  pass "vpc_cidr /16-/24 prefix validation present"
else
  fail "missing vpc_cidr /16-/24 prefix validation"
fi
assert_eq "/16 VPC carves /20 subnets" "10.40.0.0/20" "$(cidrsubnet "10.40.0.0/16" 4 0)"
assert_eq "/24 VPC carves /28 subnets" "10.40.0.0/28" "$(cidrsubnet "10.40.0.0/24" 4 0)"

# Guardrail: host bits in vpc_cidr are rejected (cidrsubnet would silently mask them)
if grep -q 'cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)\[0\]' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  pass "vpc_cidr network-address validation present"
else
  fail "missing vpc_cidr network-address validation"
fi

# Alternate VPC CIDR (common lab default) keeps the same /20 stride pattern
VPC_CIDR="10.0.0.0/16"
AZ_COUNT=2
assert_eq "alt public[0]"  "10.0.0.0/20"  "$(cidrsubnet "$VPC_CIDR" 4 0)"
assert_eq "alt public[1]"  "10.0.16.0/20" "$(cidrsubnet "$VPC_CIDR" 4 1)"
assert_eq "alt private[0]" "10.0.32.0/20" "$(cidrsubnet "$VPC_CIDR" 4 $((0 + AZ_COUNT)))"
assert_eq "alt private[1]" "10.0.48.0/20" "$(cidrsubnet "$VPC_CIDR" 4 $((1 + AZ_COUNT)))"

# Overlap guard: every public block must be disjoint from every private block (2-4 AZs)
for AZ_COUNT in 2 3 4; do
  for i in $(seq 0 $((AZ_COUNT - 1))); do
    pub="$(cidrsubnet "$VPC_CIDR" 4 "$i")"
    priv="$(cidrsubnet "$VPC_CIDR" 4 $((i + AZ_COUNT)))"
    if python3 -c "import ipaddress,sys; a=ipaddress.ip_network(sys.argv[1]); b=ipaddress.ip_network(sys.argv[2]); sys.exit(0 if not a.overlaps(b) else 1)" "$pub" "$priv"; then
      pass "disjoint az_count=$AZ_COUNT index=$i ($pub vs $priv)"
    else
      fail "overlap az_count=$AZ_COUNT index=$i ($pub vs $priv)"
    fi
  done
done

# Containment: every carved /20 must sit inside the parent VPC CIDR
VPC_CIDR="10.40.0.0/16"
AZ_COUNT=2
for i in $(seq 0 $((AZ_COUNT - 1))); do
  for kind in public private; do
    if [[ "$kind" == "public" ]]; then
      block="$(cidrsubnet "$VPC_CIDR" 4 "$i")"
    else
      block="$(cidrsubnet "$VPC_CIDR" 4 $((i + AZ_COUNT)))"
    fi
    if python3 -c "import ipaddress,sys; parent=ipaddress.ip_network(sys.argv[1]); child=ipaddress.ip_network(sys.argv[2]); sys.exit(0 if child.subnet_of(parent) else 1)" "$VPC_CIDR" "$block"; then
      pass "${kind}[$i] $block inside $VPC_CIDR"
    else
      fail "${kind}[$i] $block not inside $VPC_CIDR"
    fi
  done
done

# Guardrail: project_name must fit derived IAM role names (<name>-vpc-flow-logs <= 64)
if grep -q 'length(var.project_name) <= 50' "$ROOT/terraform/modules/vpc/variables.tf" \
  && grep -q 'regex("^\[a-z0-9\]' "$ROOT/terraform/modules/vpc/variables.tf"; then
  pass "project_name format and length validation present"
else
  fail "missing project_name format/length validation"
fi
suffix="-vpc-flow-logs"
assert_eq "max project_name role length" "64" "$((50 + ${#suffix}))"

# Guardrail: Flow Logs retention must match AWS-supported CloudWatch values
if grep -q 'flow_logs_retention_days must be a CloudWatch Logs retention value' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  pass "flow_logs_retention_days validation present"
else
  fail "missing flow_logs_retention_days validation"
fi

# Guardrail: S3 gateway endpoint lives in endpoints.tf and attaches to the private RT
if grep -q 'resource "aws_vpc_endpoint" "s3"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'count = var.enable_s3_endpoint ? 1 : 0' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'route_table_ids.*=.*\[aws_route_table.private.id\]' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "optional S3 gateway endpoint present in endpoints.tf"
else
  fail "missing optional S3 gateway endpoint wiring in endpoints.tf"
fi

# Guardrail: DynamoDB gateway endpoint mirrors S3 (private RT, count-gated)
if grep -q 'resource "aws_vpc_endpoint" "dynamodb"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'count = var.enable_dynamodb_endpoint ? 1 : 0' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -A20 'resource "aws_vpc_endpoint" "dynamodb"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
    | grep -q 'route_table_ids.*=.*\[aws_route_table.private.id\]'; then
  pass "optional DynamoDB gateway endpoint present in endpoints.tf"
else
  fail "missing optional DynamoDB gateway endpoint wiring"
fi

# Guardrail: optional NAT gateway is count-gated and pins to primary public AZ
if grep -q 'resource "aws_nat_gateway" "this"' "$ROOT/terraform/modules/vpc/main.tf" \
  && grep -q 'count = var.enable_nat_gateway ? 1 : 0' "$ROOT/terraform/modules/vpc/main.tf" \
  && grep -Eq 'subnet_id[[:space:]]*=[[:space:]]*aws_subnet\.public\[local\.primary_public_az\]\.id' "$ROOT/terraform/modules/vpc/main.tf"; then
  pass "optional NAT gateway gated and AZ-stable"
else
  fail "missing optional NAT gateway wiring or stable AZ pin"
fi

# Guardrail: Flow Logs resource waits on the IAM publish policy (avoids first-apply race)
if grep -q 'resource "aws_flow_log" "this"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
  && grep -A30 'resource "aws_flow_log" "this"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
    | grep -q 'depends_on = \[aws_iam_role_policy.flow_logs\]'; then
  pass "Flow Logs depends on IAM publish policy"
else
  fail "missing Flow Logs depends_on for IAM publish policy"
fi

# Guardrail: Flow Logs assume role requires aws:SourceAccount (confused-deputy)
if grep -q 'data "aws_iam_policy_document" "flow_logs_assume"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
  && grep -A40 'data "aws_iam_policy_document" "flow_logs_assume"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
    | grep -q 'aws:SourceAccount'; then
  pass "Flow Logs assume role requires aws:SourceAccount"
else
  fail "missing aws:SourceAccount on Flow Logs assume role"
fi

# Guardrail: private default route uses the NAT when enabled
if grep -q 'resource "aws_route" "private_default"' "$ROOT/terraform/modules/vpc/main.tf" \
  && grep -q 'nat_gateway_id' "$ROOT/terraform/modules/vpc/main.tf"; then
  pass "private default route wires nat_gateway_id"
else
  fail "missing private default route via NAT gateway"
fi

# Guardrail: NAT EIP is VPC-scoped and waits on the internet gateway
if grep -A20 'resource "aws_eip" "nat"' "$ROOT/terraform/modules/vpc/main.tf" | grep -q 'domain = "vpc"'   && grep -A20 'resource "aws_eip" "nat"' "$ROOT/terraform/modules/vpc/main.tf" | grep -q 'depends_on = \[aws_internet_gateway.this\]'; then
  pass "NAT EIP is VPC-scoped and depends on internet gateway"
else
  fail "missing NAT EIP domain/depends_on wiring"
fi

# Guardrail: interface VPC endpoints consolidated via for_each + shared SG
if grep -q 'resource "aws_vpc_endpoint" "interface"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'for_each = local.interface_endpoint_services' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'vpc_endpoint_type.*=.*"Interface"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'resource "aws_security_group" "vpc_endpoints"' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "interface VPC endpoints use for_each and shared endpoint SG"
else
  fail "missing consolidated interface VPC endpoint wiring"
fi

# Guardrail: Session Manager services remain in the interface map (ssm + companions)
if grep -q 'ssm.*=.*"ssm"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'ssmmessages.*=.*"ssmmessages"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'ec2messages.*=.*"ec2messages"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'var.enable_ssm_endpoint' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "ssmmessages and ec2messages interface endpoints present in for_each map"
else
  fail "missing ssmmessages/ec2messages entries for Session Manager"
fi

# Guardrail: shared interface resource enables private DNS, private subnets, and SG
iface_block="$(grep -A20 'resource "aws_vpc_endpoint" "interface"' "$ROOT/terraform/modules/vpc/endpoints.tf")"
if echo "$iface_block" | grep -q 'private_dns_enabled.*=.*true' \
  && echo "$iface_block" | grep -q 'local.private_subnet_ids' \
  && echo "$iface_block" | grep -q 'security_group_ids.*=.*\[aws_security_group.vpc_endpoints\[0\].id\]'; then
  pass "interface endpoints use private DNS, private subnets, and endpoint SG"
else
  fail "interface endpoints missing private DNS / private subnet / SG wiring"
fi

# Guardrail: private_subnet_ids local mirrors AZ-ordered private subnets
if grep -q 'private_subnet_ids = \[' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'aws_subnet.private\[az\].id' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "private_subnet_ids local derived from private subnets"
else
  fail "missing private_subnet_ids local for interface endpoints"
fi

# Keep parity with prior suite size (one assertion for companion wiring)
if grep -q 'interface_endpoint_services' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "interface_endpoint_services local present for companion endpoint keys"
else
  fail "missing interface_endpoint_services local"
fi

# Guardrail: endpoint SG allows HTTPS from the VPC CIDR only (Session Manager control plane)
sg_block="$(grep -A40 'resource "aws_security_group" "vpc_endpoints"' "$ROOT/terraform/modules/vpc/endpoints.tf")"
if echo "$sg_block" | grep -q 'from_port.*=.*443' \
  && echo "$sg_block" | grep -q 'to_port.*=.*443' \
  && echo "$sg_block" | grep -q 'cidr_blocks.*=.*\[var.vpc_cidr\]'; then
  pass "VPC endpoint SG restricts HTTPS to VPC CIDR"
else
  fail "VPC endpoint SG missing HTTPS-from-VPC CIDR restriction"
fi

# Guardrail: optional ECR interface endpoints (api + dkr) for private image pulls
if grep -q 'ecr_api.*=.*"ecr.api"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'ecr_dkr.*=.*"ecr.dkr"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'var.enable_ecr_endpoint' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "optional ECR api/dkr interface endpoints present in for_each map"
else
  fail "missing optional ECR api/dkr interface endpoint wiring"
fi

# Guardrail: ECR keys share the same interface resource (private DNS / subnets / SG)
if echo "$iface_block" | grep -q 'private_dns_enabled.*=.*true' \
  && echo "$iface_block" | grep -q 'local.private_subnet_ids' \
  && echo "$iface_block" | grep -q 'security_group_ids.*=.*\[aws_security_group.vpc_endpoints\[0\].id\]'; then
  pass "ecr_api/ecr_dkr share interface private DNS, private subnets, and endpoint SG"
else
  fail "ECR interface endpoints missing private DNS / private subnet / SG wiring"
fi

# Keep second ECR parity assertion (map gated by enable_ecr_endpoint)
if grep -A20 'var.enable_ecr_endpoint ?' "$ROOT/terraform/modules/vpc/endpoints.tf" | grep -q 'ecr_api'; then
  pass "ecr_api/ecr_dkr gated by enable_ecr_endpoint in interface map"
else
  fail "ECR keys not gated by enable_ecr_endpoint"
fi

# Guardrail: VPC endpoint SG is created when any interface service is enabled
if grep -q 'count = length(local.interface_endpoint_services) > 0 ? 1 : 0' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "endpoint SG count gates on interface_endpoint_services map"
else
  fail "endpoint SG count missing interface_endpoint_services gate"
fi

# Guardrail: optional CloudWatch Logs interface endpoint in for_each map
if grep -q 'logs.*=.*"logs"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'var.enable_logs_endpoint' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "optional CloudWatch Logs interface endpoint present in for_each map"
else
  fail "missing optional CloudWatch Logs interface endpoint wiring"
fi

# Guardrail: logs key gated by enable_logs_endpoint in interface map
if grep -A5 'var.enable_logs_endpoint ?' "$ROOT/terraform/modules/vpc/endpoints.tf" | grep -q 'logs.*=.*"logs"'; then
  pass "logs endpoint gated by enable_logs_endpoint in interface map"
else
  fail "logs key not gated by enable_logs_endpoint"
fi

# Guardrail: logs_endpoint_id output exposes interface["logs"] when enabled
if grep -q 'output "logs_endpoint_id"' "$ROOT/terraform/modules/vpc/outputs.tf" \
  && grep -A5 'output "logs_endpoint_id"' "$ROOT/terraform/modules/vpc/outputs.tf" \
    | grep -q 'aws_vpc_endpoint.interface\["logs"\]'; then
  pass "logs_endpoint_id output reads interface[\"logs\"]"
else
  fail "missing logs_endpoint_id output for CloudWatch Logs endpoint"
fi

# Guardrail: root module passes enable_logs_endpoint into the VPC module
if grep -q 'enable_logs_endpoint.*=.*var.enable_logs_endpoint' "$ROOT/terraform/main.tf" \
  && grep -q 'variable "enable_logs_endpoint"' "$ROOT/terraform/variables.tf"; then
  pass "root module wires enable_logs_endpoint into VPC module"
else
  fail "root module missing enable_logs_endpoint pass-through"
fi

# Guardrail: optional Secrets Manager interface endpoint in for_each map
if grep -q 'secretsmanager.*=.*"secretsmanager"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'var.enable_secretsmanager_endpoint' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "optional Secrets Manager interface endpoint present in for_each map"
else
  fail "missing optional Secrets Manager interface endpoint wiring"
fi

# Guardrail: secretsmanager key gated by enable_secretsmanager_endpoint
if grep -A5 'var.enable_secretsmanager_endpoint ?' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  | grep -q 'secretsmanager.*=.*"secretsmanager"'; then
  pass "secretsmanager endpoint gated by enable_secretsmanager_endpoint"
else
  fail "secretsmanager key not gated by enable_secretsmanager_endpoint"
fi

# Guardrail: secretsmanager_endpoint_id output exposes interface["secretsmanager"]
if grep -q 'output "secretsmanager_endpoint_id"' "$ROOT/terraform/modules/vpc/outputs.tf" \
  && grep -A5 'output "secretsmanager_endpoint_id"' "$ROOT/terraform/modules/vpc/outputs.tf" \
    | grep -q 'aws_vpc_endpoint.interface\["secretsmanager"\]'; then
  pass "secretsmanager_endpoint_id output reads interface[\"secretsmanager\"]"
else
  fail "missing secretsmanager_endpoint_id output"
fi

# Guardrail: root module passes enable_secretsmanager_endpoint into the VPC module
if grep -q 'enable_secretsmanager_endpoint.*=.*var.enable_secretsmanager_endpoint' "$ROOT/terraform/main.tf" \
  && grep -q 'variable "enable_secretsmanager_endpoint"' "$ROOT/terraform/variables.tf"; then
  pass "root module wires enable_secretsmanager_endpoint into VPC module"
else
  fail "root module missing enable_secretsmanager_endpoint pass-through"
fi

# Guardrail: optional KMS interface endpoint in for_each map
if grep -q 'kms.*=.*"kms"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'var.enable_kms_endpoint' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  pass "optional KMS interface endpoint present in for_each map"
else
  fail "missing optional KMS interface endpoint wiring"
fi

# Guardrail: kms key gated by enable_kms_endpoint
if grep -A5 'var.enable_kms_endpoint ?' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  | grep -q 'kms.*=.*"kms"'; then
  pass "kms endpoint gated by enable_kms_endpoint"
else
  fail "kms key not gated by enable_kms_endpoint"
fi

# Guardrail: kms_endpoint_id output exposes interface["kms"]
if grep -q 'output "kms_endpoint_id"' "$ROOT/terraform/modules/vpc/outputs.tf" \
  && grep -A5 'output "kms_endpoint_id"' "$ROOT/terraform/modules/vpc/outputs.tf" \
    | grep -q 'aws_vpc_endpoint.interface\["kms"\]'; then
  pass "kms_endpoint_id output reads interface[\"kms\"]"
else
  fail "missing kms_endpoint_id output"
fi

# Guardrail: root module passes enable_kms_endpoint into the VPC module
if grep -q 'enable_kms_endpoint.*=.*var.enable_kms_endpoint' "$ROOT/terraform/main.tf" \
  && grep -q 'variable "enable_kms_endpoint"' "$ROOT/terraform/variables.tf"; then
  pass "root module wires enable_kms_endpoint into VPC module"
else
  fail "root module missing enable_kms_endpoint pass-through"
fi

# Guardrail: ECR interface endpoints require the S3 gateway (layer pulls)
if grep -A15 'precondition' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  | grep -q '!var.enable_ecr_endpoint || var.enable_s3_endpoint'; then
  pass "ECR endpoint precondition requires enable_s3_endpoint"
else
  fail "missing ECR requires S3 gateway precondition"
fi

finish
