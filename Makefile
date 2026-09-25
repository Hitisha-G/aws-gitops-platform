# Local helpers for aws-gitops-platform (no remote state required).

TF_DIR := terraform
TEST_DIR := tests

.PHONY: help fmt validate init test ci clean

help:
	@printf '%s\n' \
		'Targets:' \
		'  make fmt       - terraform fmt -recursive' \
		'  make init      - terraform init -backend=false' \
		'  make validate  - fmt check + init + validate' \
		'  make test      - shell unit checks under tests/' \
		'  make ci        - test + validate (mirrors GitHub Actions)' \
		'  make clean     - remove local .terraform dirs'

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

init:
	cd $(TF_DIR) && terraform init -backend=false

validate: init
	cd $(TF_DIR) && terraform fmt -check -recursive
	cd $(TF_DIR) && terraform validate

test:
	@for script in $(TEST_DIR)/*.sh; do \
		echo "==> $$script"; \
		bash "$$script"; \
	done

ci: test validate

clean:
	rm -rf $(TF_DIR)/.terraform
	find $(TF_DIR) -name '.terraform' -type d -prune -exec rm -rf {} +
