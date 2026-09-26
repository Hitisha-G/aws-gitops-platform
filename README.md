# aws-gitops-platform

GitOps-ready AWS platform foundation: Terraform modules, sample Helm chart, and CI that validates infrastructure code on every push.

Built for platform / DevOps workflows — local-friendly validation first, with a clear path to EKS + OIDC deploys.

## What's in here

- `terraform/` — root stack and reusable modules (VPC with NAT, flow logs, S3/DynamoDB endpoints; EKS/IRSA next)
- `charts/sample-app` — demo workload chart (planned)
- `.github/workflows/ci.yml` — `terraform fmt` + `validate`, ShellCheck on helper scripts, Helm lint (when charts land)
- `tests/` — shell unit checks for VPC CIDR carving (run in CI)

## Repository layout

```
Makefile            # local fmt / init / validate / test / ci helpers
terraform/
  main.tf           # wires root variables into modules
  variables.tf      # region, project name, VPC CIDR, AZs, NAT, flow logs, endpoints
  providers.tf      # AWS provider
  versions.tf       # required Terraform / provider versions
  outputs.tf        # stack outputs (VPC, subnets, NAT, flow logs, endpoints)
  terraform.tfvars.example
  modules/
    vpc/
      main.tf         # VPC, subnets, route tables, NAT
      flow_logs.tf    # optional CloudWatch Flow Logs + IAM
      endpoints.tf    # optional S3 / DynamoDB gateway endpoints
      variables.tf
      outputs.tf
tests/
  vpc_cidr_layout_test.sh
```

Default region is `ap-south-1` (Mumbai) so local experiments match common India-region targets.

## VPC module

The `terraform/modules/vpc` module expects:

| Input | Purpose |
| --- | --- |
| `project_name` | Prefix for resource Name tags |
| `vpc_cidr` | CIDR for the VPC (default root value `10.40.0.0/16`) |
| `availability_zones` | One public + one private subnet per AZ (minimum two, no duplicates) |
| `tags` | Optional map merged onto every resource |
| `enable_nat_gateway` | When true (default), place one NAT in the first public subnet and route private `0.0.0.0/0` through it |
| `enable_flow_logs` | When true, send VPC Flow Logs (ALL traffic) to CloudWatch Logs |
| `flow_logs_retention_days` | CloudWatch retention for the flow-log group (default `14`) |
| `enable_s3_endpoint` | When true (default), attach a gateway VPC endpoint for S3 to the private route table |
| `enable_dynamodb_endpoint` | When true (default), attach a gateway VPC endpoint for DynamoDB to the private route table |

Shared tag and CIDR locals live in the module so subnet math and tagging stay consistent as more modules are added. Public and private subnets use `for_each` keyed by AZ name so reordering the AZ list does not force needless replacements.

### NAT gateway

Private subnets share a dedicated route table. When `enable_nat_gateway` is true, a single EIP + NAT gateway lands in the lexicographically first public subnet AZ, and a standalone `aws_route` points private default traffic at that NAT. Set the flag to false for cost-sensitive labs that do not need private egress.

### VPC Flow Logs

Flow logs are off by default. Set `enable_flow_logs = true` (root or module) to create:

1. A CloudWatch Logs group under `/aws/vpc/<project>/flow-logs`
2. An IAM role assumed by `vpc-flow-logs.amazonaws.com`
3. An inline policy scoped to that log group
4. An `aws_flow_log` resource for the VPC (`traffic_type = ALL`)

The flow-log resource depends on the IAM policy so the first apply does not race CreateLogStream with a missing permission. Retention must be a value AWS CloudWatch Logs accepts (for example 1, 7, 14, 30, 90, 365).

Useful root outputs when enabled: `flow_log_id`, `flow_log_group_name`, plus `nat_gateway_id` when NAT is on.

### Gateway VPC endpoints

Private workloads often pull from S3 or DynamoDB. Gateway endpoints keep that traffic on the AWS network and avoid NAT charges for those prefixes.

When `enable_s3_endpoint` or `enable_dynamodb_endpoint` is true, the module creates the matching `aws_vpc_endpoint` (type `Gateway`) in the current region and associates it with the private route table. Both flags default to true so a fresh apply gets private access without extra knobs; set either to false if a lab stack should skip that service.

Endpoints live in `terraform/modules/vpc/endpoints.tf`, separate from networking and flow-log resources, so reviews stay focused when you only change egress or logging.

## Quick start

With Make (preferred locally):

```bash
make ci
```

Or the Terraform steps by hand:

```bash
cd terraform
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

Copy `terraform/terraform.tfvars.example` when you want named values for a lab apply. Optional unit tests:

```bash
make test
# or: bash tests/vpc_cidr_layout_test.sh
```

CI runs fmt, validate, and those shell checks on every push to `main`.

## Roadmap

- [x] Repo scaffold + CI
- [x] VPC module (subnets, NAT, optional flow logs, S3/DynamoDB gateway endpoints)
- [ ] EKS module + IRSA stubs
- [ ] Sample app Helm chart
- [ ] Docs: OIDC deploy from GitHub Actions

## License

MIT
