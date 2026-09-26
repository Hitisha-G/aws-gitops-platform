#!/usr/bin/env bash
# Unit checks for the VPC module's public/private CIDR layout.
# Mirrors locals in terraform/modules/vpc/main.tf:
#   public  = cidrsubnet(vpc_cidr, 4, i)
#   private = cidrsubnet(vpc_cidr, 4, i + az_count)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $label ($actual)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label expected=$expected actual=$actual" >&2
    FAIL=$((FAIL + 1))
  fi
}

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
  echo "PASS: AZ validation present in module variables"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing AZ count validation in module variables" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: duplicate AZ entries must be rejected (for_each keys collide otherwise)
if grep -q 'length(toset(var.availability_zones))' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  echo "PASS: AZ uniqueness validation present in module variables"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing AZ uniqueness validation in module variables" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: undersized AZ counts vs subnet carve must fail before apply
if grep -q 'local.az_count \* 2 <= pow(2, local.subnet_newbits)' \
  "$ROOT/terraform/modules/vpc/main.tf"; then
  echo "PASS: VPC subnet capacity precondition present"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing VPC subnet capacity precondition" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: invalid vpc_cidr rejected at variable validation
if grep -q 'can(cidrsubnet(var.vpc_cidr, 4, 0))' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  echo "PASS: vpc_cidr cidrsubnet validation present"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing vpc_cidr cidrsubnet validation" >&2
  FAIL=$((FAIL + 1))
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
      echo "PASS: disjoint az_count=$AZ_COUNT index=$i ($pub vs $priv)"
      PASS=$((PASS + 1))
    else
      echo "FAIL: overlap az_count=$AZ_COUNT index=$i ($pub vs $priv)" >&2
      FAIL=$((FAIL + 1))
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
      echo "PASS: $kind[$i] $block inside $VPC_CIDR"
      PASS=$((PASS + 1))
    else
      echo "FAIL: $kind[$i] $block not inside $VPC_CIDR" >&2
      FAIL=$((FAIL + 1))
    fi
  done
done

# Guardrail: Flow Logs retention must match AWS-supported CloudWatch values
if grep -q 'flow_logs_retention_days must be a CloudWatch Logs retention value' \
  "$ROOT/terraform/modules/vpc/variables.tf"; then
  echo "PASS: flow_logs_retention_days validation present"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing flow_logs_retention_days validation" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: S3 gateway endpoint lives in endpoints.tf and attaches to the private RT
if grep -q 'resource "aws_vpc_endpoint" "s3"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'count = var.enable_s3_endpoint ? 1 : 0' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'route_table_ids.*=.*\[aws_route_table.private.id\]' "$ROOT/terraform/modules/vpc/endpoints.tf"; then
  echo "PASS: optional S3 gateway endpoint present in endpoints.tf"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing optional S3 gateway endpoint wiring in endpoints.tf" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: DynamoDB gateway endpoint mirrors S3 (private RT, count-gated)
if grep -q 'resource "aws_vpc_endpoint" "dynamodb"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -q 'count = var.enable_dynamodb_endpoint ? 1 : 0' "$ROOT/terraform/modules/vpc/endpoints.tf" \
  && grep -A20 'resource "aws_vpc_endpoint" "dynamodb"' "$ROOT/terraform/modules/vpc/endpoints.tf" \
    | grep -q 'route_table_ids.*=.*\[aws_route_table.private.id\]'; then
  echo "PASS: optional DynamoDB gateway endpoint present in endpoints.tf"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing optional DynamoDB gateway endpoint wiring" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: optional NAT gateway is count-gated and pins to primary public AZ
if grep -q 'resource "aws_nat_gateway" "this"' "$ROOT/terraform/modules/vpc/main.tf" \
  && grep -q 'count = var.enable_nat_gateway ? 1 : 0' "$ROOT/terraform/modules/vpc/main.tf" \
  && grep -q 'subnet_id = aws_subnet.public\[local.primary_public_az\].id' "$ROOT/terraform/modules/vpc/main.tf"; then
  echo "PASS: optional NAT gateway gated and AZ-stable"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing optional NAT gateway wiring or stable AZ pin" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: Flow Logs resource waits on the IAM publish policy (avoids first-apply race)
if grep -q 'resource "aws_flow_log" "this"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
  && grep -A30 'resource "aws_flow_log" "this"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
    | grep -q 'depends_on = \[aws_iam_role_policy.flow_logs\]'; then
  echo "PASS: Flow Logs depends on IAM publish policy"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing Flow Logs depends_on for IAM publish policy" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: Flow Logs assume role requires aws:SourceAccount (confused-deputy)
if grep -q 'data "aws_iam_policy_document" "flow_logs_assume"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
  && grep -A40 'data "aws_iam_policy_document" "flow_logs_assume"' "$ROOT/terraform/modules/vpc/flow_logs.tf" \
    | grep -q 'aws:SourceAccount'; then
  echo "PASS: Flow Logs assume role requires aws:SourceAccount"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing aws:SourceAccount on Flow Logs assume role" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: private default route uses the NAT when enabled
if grep -q 'resource "aws_route" "private_default"' "$ROOT/terraform/modules/vpc/main.tf" \
  && grep -q 'nat_gateway_id' "$ROOT/terraform/modules/vpc/main.tf"; then
  echo "PASS: private default route wires nat_gateway_id"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing private default route via NAT gateway" >&2
  FAIL=$((FAIL + 1))
fi

# Guardrail: NAT EIP is VPC-scoped and waits on the internet gateway
if grep -A20 'resource "aws_eip" "nat"' "$ROOT/terraform/modules/vpc/main.tf" | grep -q 'domain = "vpc"'   && grep -A20 'resource "aws_eip" "nat"' "$ROOT/terraform/modules/vpc/main.tf" | grep -q 'depends_on = \[aws_internet_gateway.this\]'; then
  echo "PASS: NAT EIP is VPC-scoped and depends on internet gateway"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing NAT EIP domain/depends_on wiring" >&2
  FAIL=$((FAIL + 1))
fi

echo "---"
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
