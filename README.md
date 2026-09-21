# aws-gitops-platform

GitOps-ready AWS platform foundation: Terraform modules, sample Helm chart, and CI that validates infrastructure code on every push.

Built for platform / DevOps workflows — local-friendly validation first, with a clear path to EKS + OIDC deploys.

## What's in here

- `terraform/` — root stack and reusable modules (VPC first, then EKS/IRSA)
- `charts/sample-app` — demo workload chart
- `.github/workflows/ci.yml` — `terraform fmt` + `validate`, Helm lint

## Quick start

```bash
cd terraform
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

## Roadmap

- [x] Repo scaffold + CI
- [ ] VPC module
- [ ] EKS module + IRSA stubs
- [ ] Sample app Helm chart
- [ ] Docs: OIDC deploy from GitHub Actions

## License

MIT
