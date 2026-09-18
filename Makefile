.PHONY: lint test guard-estate guard-platform \
	bootstrap-plan bootstrap-apply destroy-bootstrap \
	plan-estate apply-estate destroy-estate

# Everything here is Terraform (CLAUDE.md #6). This Makefile only sequences
# init/plan/apply/destroy per layer and enforces the account guard first —
# it never provisions anything itself.

lint:
	terraform fmt -check -recursive
	@for dir in estate/iac/bootstrap estate/iac/baseline estate/iac/network; do \
		if [ -n "$$(ls -A $$dir/*.tf 2>/dev/null)" ]; then \
			echo "validating $$dir"; \
			terraform -chdir=$$dir init -backend=false -input=false >/dev/null; \
			terraform -chdir=$$dir validate; \
		fi \
	done

test:
	@if [ -d tests ]; then pytest -m "not aws"; else echo "no tests yet"; fi

# The bootstrap layer creates condor-bootstrap, so it cannot itself run as
# condor-bootstrap. Runs as the operator's own AIDiscoveryAccess profile.
bootstrap-plan:
	terraform -chdir=estate/iac/bootstrap init -input=false
	terraform -chdir=estate/iac/bootstrap plan

bootstrap-apply:
	terraform -chdir=estate/iac/bootstrap apply

# Deliberately separate from destroy-estate: tears down the state bucket and
# condor-bootstrap itself. Only after baseline and network are already gone.
destroy-bootstrap:
	terraform -chdir=estate/iac/bootstrap destroy

guard-estate:
	AWS_PROFILE=condor-bootstrap ./scripts/guard.sh estate

guard-platform:
	AWS_PROFILE=dp-deployer ./scripts/guard.sh platform

# Everything after bootstrap runs as condor-bootstrap, in dependency order.
plan-estate: guard-estate
	terraform -chdir=estate/iac/baseline init -input=false
	terraform -chdir=estate/iac/baseline plan
	terraform -chdir=estate/iac/network init -input=false
	terraform -chdir=estate/iac/network plan

apply-estate: guard-estate
	terraform -chdir=estate/iac/baseline apply
	terraform -chdir=estate/iac/network apply

# Reverse dependency order: network before baseline. Neither touches
# bootstrap — see destroy-bootstrap.
destroy-estate: guard-estate
	terraform -chdir=estate/iac/network destroy
	terraform -chdir=estate/iac/baseline destroy
