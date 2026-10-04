# Local helpers for aws-gitops-platform (no remote state required).

TF_DIR := terraform
TEST_DIR := tests

.DEFAULT_GOAL := help

.PHONY: help fmt fmt-check validate init test lint shellcheck ci clean

help:
	@printf '%s\n' \
		'Targets:' \
		'  make fmt        - terraform fmt -recursive' \
		'  make fmt-check  - terraform fmt -check -diff -recursive' \
		'  make init       - terraform init -backend=false' \
		'  make validate   - fmt check + init + validate' \
		'  make lint       - tflint --init + tflint --recursive (needs tflint)' \
		'  make shellcheck - shellcheck tests/*.sh (needs shellcheck)' \
		'  make test       - shell unit checks under tests/' \
		'  make ci         - test + validate + lint (mirrors GitHub Actions)' \
		'  make clean      - remove local .terraform dirs'

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

fmt-check:
	cd $(TF_DIR) && terraform fmt -check -diff -recursive

init:
	cd $(TF_DIR) && terraform init -backend=false

validate: init
	cd $(TF_DIR) && terraform fmt -check -recursive
	cd $(TF_DIR) && terraform validate

lint:
	cd $(TF_DIR) && tflint --init
	cd $(TF_DIR) && tflint --recursive

shellcheck:
	shellcheck $(TEST_DIR)/*.sh

test:
	@for script in $(TEST_DIR)/*.sh; do \
		echo "==> $$script"; \
		bash "$$script"; \
	done

ci: test validate lint

clean:
	rm -rf $(TF_DIR)/.terraform
	find $(TF_DIR) -name '.terraform' -type d -prune -exec rm -rf {} +
