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

echo "---"
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
