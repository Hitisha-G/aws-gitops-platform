# aws-gitops-platform

GitOps-ready AWS platform foundation: Terraform modules, sample Helm chart, and CI that validates infrastructure code on every push.

Built for platform / DevOps workflows — local-friendly validation first, with a clear path to EKS + OIDC deploys.

## What's in here

- `terraform/` — root stack and reusable modules (VPC first, then EKS/IRSA)
- `charts/sample-app` — demo workload chart (planned)
- `.github/workflows/ci.yml` — `terraform fmt` + `validate`, Helm lint (when charts land)

## Repository layout

```
terraform/
  main.tf           # wires root variables into modules
  variables.tf      # region, project name, VPC CIDR, AZs
  providers.tf      # AWS provider
  versions.tf       # required Terraform / provider versions
  outputs.tf        # stack outputs
  modules/
    vpc/            # VPC, public/private subnets, shared tags
```

Default region is `ap-south-1` (Mumbai) so local experiments match common India-region targets.

## VPC module

The `terraform/modules/vpc` module expects:

| Input | Purpose |
| --- | --- |
| `project_name` | Prefix for resource Name tags |
| `vpc_cidr` | CIDR for the VPC (default root value `10.40.0.0/16`) |
| `availability_zones` | One public + one private subnet per AZ |
| `tags` | Optional map merged onto every resource |

Shared tag and CIDR locals live in the module so subnet math and tagging stay consistent as more modules are added.

## Quick start

```bash
cd terraform
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

CI runs the same fmt/validate checks on every push to `main`.

## Roadmap

- [x] Repo scaffold + CI
- [x] VPC module
- [ ] EKS module + IRSA stubs
- [ ] Sample app Helm chart
- [ ] Docs: OIDC deploy from GitHub Actions

## License

MIT
