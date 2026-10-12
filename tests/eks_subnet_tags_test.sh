#!/usr/bin/env bash
# Guardrail checks for optional EKS subnet discovery tags.
# When enable_eks_subnet_tags is true, public subnets get
# kubernetes.io/role/elb and private get kubernetes.io/role/internal-elb.
# An optional eks_cluster_tag adds kubernetes.io/cluster/<name>=shared.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_MAIN="$ROOT/terraform/modules/vpc/main.tf"
MODULE_VARS="$ROOT/terraform/modules/vpc/variables.tf"
ROOT_VARS="$ROOT/terraform/variables.tf"
ROOT_MAIN="$ROOT/terraform/main.tf"
TFVARS_EXAMPLE="$ROOT/terraform/terraform.tfvars.example"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# Print the body of `variable "<name>" { ... }` from a .tf file.
variable_block() {
  local file="$1" name="$2"
  awk -v name="$name" '
    $0 ~ "^variable \"" name "\"" { inside = 1 }
    inside { print }
    inside && /^}/ { exit }
  ' "$file"
}

default_of() {
  variable_block "$1" "$2" | sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' | tr -d '"'
}

# 1. Module declares both variables with safe defaults (off / empty).
if grep -q 'variable "enable_eks_subnet_tags"' "$MODULE_VARS"; then
  pass "module declares enable_eks_subnet_tags"
else
  fail "module missing enable_eks_subnet_tags variable"
fi
if grep -q 'variable "eks_cluster_tag"' "$MODULE_VARS"; then
  pass "module declares eks_cluster_tag"
else
  fail "module missing eks_cluster_tag variable"
fi

module_bool_default="$(default_of "$MODULE_VARS" enable_eks_subnet_tags)"
module_name_default="$(default_of "$MODULE_VARS" eks_cluster_tag)"
if [[ "$module_bool_default" == "false" ]]; then
  pass "module enable_eks_subnet_tags defaults to false"
else
  fail "module enable_eks_subnet_tags default is '$module_bool_default' (expected false)"
fi
if [[ "$module_name_default" == "" ]]; then
  pass "module eks_cluster_tag defaults to empty string"
else
  fail "module eks_cluster_tag default is '$module_name_default' (expected empty)"
fi

# 2. Root mirrors the same variables and defaults.
if grep -q 'variable "enable_eks_subnet_tags"' "$ROOT_VARS" \
  && grep -q 'variable "eks_cluster_tag"' "$ROOT_VARS"; then
  pass "root declares enable_eks_subnet_tags and eks_cluster_tag"
else
  fail "root missing EKS subnet tag variables"
fi
root_bool_default="$(default_of "$ROOT_VARS" enable_eks_subnet_tags)"
root_name_default="$(default_of "$ROOT_VARS" eks_cluster_tag)"
if [[ "$root_bool_default" == "false" && "$root_name_default" == "" ]]; then
  pass "root EKS tag defaults match module (false / empty)"
else
  fail "root EKS tag defaults drifted (bool=$root_bool_default name='$root_name_default')"
fi

# 3. Root module forwards both variables into the VPC module.
if grep -Eq '^[[:space:]]*enable_eks_subnet_tags[[:space:]]*=[[:space:]]*var\.enable_eks_subnet_tags' "$ROOT_MAIN" \
  && grep -Eq '^[[:space:]]*eks_cluster_tag[[:space:]]*=[[:space:]]*var\.eks_cluster_tag' "$ROOT_MAIN"; then
  pass "root module passes EKS subnet tag vars into VPC module"
else
  fail "root module does not pass EKS subnet tag vars into VPC module"
fi

# 4. Module locals build the role tags and optional cluster shared tag.
if grep -q 'eks_public_subnet_tags' "$MODULE_MAIN" \
  && grep -q 'eks_private_subnet_tags' "$MODULE_MAIN" \
  && grep -q 'eks_cluster_shared_tag' "$MODULE_MAIN"; then
  pass "module locals define public/private EKS tag maps"
else
  fail "module locals missing EKS subnet tag maps"
fi

if grep -q 'kubernetes.io/role/elb' "$MODULE_MAIN" \
  && grep -q 'kubernetes.io/role/internal-elb' "$MODULE_MAIN"; then
  pass "module wires kubernetes.io/role/elb and internal-elb tags"
else
  fail "module missing kubernetes.io/role elb/internal-elb tag keys"
fi

if grep -qF "kubernetes.io/cluster/\${var.eks_cluster_tag}" "$MODULE_MAIN"; then
  pass "module wires kubernetes.io/cluster/<eks_cluster_tag> shared tag"
else
  fail "module missing kubernetes.io/cluster/<eks_cluster_tag> shared tag"
fi

# 5. Subnet resources merge the EKS tag locals (gated off when flag is false).
public_block="$(awk '/^resource "aws_subnet" "public"/ { inside = 1 } inside { print } inside && /^}/ { exit }' "$MODULE_MAIN")"
private_block="$(awk '/^resource "aws_subnet" "private"/ { inside = 1 } inside { print } inside && /^}/ { exit }' "$MODULE_MAIN")"
if printf '%s\n' "$public_block" | grep -q 'local.eks_public_subnet_tags'; then
  pass "public subnet tags merge local.eks_public_subnet_tags"
else
  fail "public subnet resource does not merge eks_public_subnet_tags"
fi
if printf '%s\n' "$private_block" | grep -q 'local.eks_private_subnet_tags'; then
  pass "private subnet tags merge local.eks_private_subnet_tags"
else
  fail "private subnet resource does not merge eks_private_subnet_tags"
fi

# 6. Cluster shared tag only applies when both the flag is on and the name is set.
if grep -q 'var.enable_eks_subnet_tags && var.eks_cluster_tag != ""' "$MODULE_MAIN"; then
  pass "cluster shared tag gated on enable_eks_subnet_tags and non-empty eks_cluster_tag"
else
  fail "cluster shared tag missing dual gate (flag + non-empty name)"
fi

# 7. tfvars example documents both knobs with safe defaults.
if grep -Eq '^[[:space:]]*enable_eks_subnet_tags[[:space:]]*=' "$TFVARS_EXAMPLE" \
  && grep -Eq '^[[:space:]]*eks_cluster_tag[[:space:]]*=' "$TFVARS_EXAMPLE"; then
  pass "tfvars example includes enable_eks_subnet_tags and eks_cluster_tag"
else
  fail "tfvars example missing EKS subnet tag knobs"
fi

echo "---"
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
