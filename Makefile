# Developer entry points. Tool versions are pinned here and in CI so local
# runs and CI behave the same.
CHART            ?= charts/appwrite
RELEASE          ?= appwrite
NAMESPACE        ?= appwrite
KUBE_VERSIONS    ?= 1.29.0 1.32.0 1.35.0 1.37.0
APP_VERSION      ?= $(shell awk '/^appVersion:/ {gsub(/"/, "", $$2); print $$2}' $(CHART)/Chart.yaml)
KIND_CLUSTER     ?= appwrite
VALUES           ?= $(CHART)/ci/default-values.yaml
HELM_UNITTEST    ?= v1.2.1
HELM_SCHEMA      ?= v2.6.0
ZIZMOR           ?= 1.30.1
CRD_SCHEMAS      ?= https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
# Values files in examples/, each a space-free list of files joined with "+"
# (applied in order with -f). Overlays are checked on top of a base file.
EXAMPLES         ?= local minimal production minimal+external-services minimal+aws minimal+functions production+external-services production+aws production+functions-existing-secrets minimal+external-services+functions-existing-secrets minimal+aws+functions-existing-secrets minimal+gcp minimal+azure production+gcp production+azure minimal+gcp+functions-existing-secrets

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: tools
tools: ## Install the Helm plugins used by the targets below
	helm plugin list | grep -q '^unittest' || helm plugin install https://github.com/helm-unittest/helm-unittest/releases/download/$(HELM_UNITTEST)/unittest-$(patsubst v%,%,$(HELM_UNITTEST)).tgz --verify=false
	helm plugin list | grep -q '^schema' || helm plugin install https://github.com/losisin/helm-values-schema-json --version $(HELM_SCHEMA) --verify=false

.PHONY: lint
lint: ## Lint the chart with ct and helm lint --strict for every ci/ scenario
	ct lint --config ct.yaml --all
	@for f in $(CHART)/ci/*-values.yaml; do \
		echo "==> helm lint --strict -f $$f"; \
		helm lint --strict $(CHART) -f $$f || exit 1; \
	done

.PHONY: unittest
unittest: ## Run helm-unittest suites
	helm unittest --strict $(CHART)

.PHONY: unittest-update
unittest-update: ## Run helm-unittest and update snapshots
	helm unittest --strict --update-snapshot $(CHART)

.PHONY: schema
schema: ## Regenerate values.schema.json from values.yaml annotations
	cd $(CHART) && helm schema
	python3 hack/schema-postprocess.py $(CHART)/values.schema.json

.PHONY: docs
docs: ## Regenerate the chart README with helm-docs
	helm-docs --chart-search-root charts --template-files README.md.gotmpl

.PHONY: env-defaults
env-defaults: ## Regenerate files/env-defaults.yaml from Appwrite's variables.php at APP_VERSION
	curl -fsSL "https://raw.githubusercontent.com/appwrite/appwrite/$(APP_VERSION)/app/config/variables.php" -o .variables.php
	@# Into a temporary file first: PHP prints fatal errors to stdout.
	php hack/gen-env-defaults.php .variables.php $(APP_VERSION) > .env-defaults.yaml || { rm -f .variables.php .env-defaults.yaml; exit 1; }
	mv .env-defaults.yaml $(CHART)/files/env-defaults.yaml
	rm -f .variables.php

.PHONY: images
images: ## Sync the artifacthub.io/images annotation with values.yaml
	hack/chart-images.sh

.PHONY: update-images
update-images: ## Bump every pinned image tag in values.yaml to the newest in its registry (ARGS="--dry-run --all")
	hack/update-images.sh $(ARGS)

.PHONY: generate
generate: schema images docs ## Regenerate all generated files

.PHONY: check-generated
check-generated: generate ## Fail if generated files are out of date
	@git diff --exit-code -- $(CHART)/values.schema.json $(CHART)/README.md $(CHART)/Chart.yaml \
		|| (echo "Generated files are stale: run 'make generate' and commit the result." && exit 1)

.PHONY: changes
changes: ## Write the CHANGELOG.md section of the chart version into artifacthub.io/changes
	hack/changelog-changes.sh --write

.PHONY: check-changes
check-changes: ## Fail if artifacthub.io/changes doesn't match CHANGELOG.md (no-op until CHANGELOG.md has a section for the chart version)
	hack/changelog-changes.sh --check

.PHONY: check-versions
check-versions: ## Fail if the docs, examples or workflows name an Appwrite version other than appVersion
	hack/check-versions.sh

.PHONY: kubeconform
kubeconform: ## Validate rendered manifests against several Kubernetes versions
	@for f in $(CHART)/ci/*-values.yaml; do \
		for v in $(KUBE_VERSIONS); do \
			echo "==> kubeconform $$f (k8s $$v)"; \
			out=$$(helm template $(RELEASE) $(CHART) -n $(NAMESPACE) -f $$f --kube-version $$v) || exit 1; \
			printf '%s\n' "$$out" | kubeconform -strict -summary -kubernetes-version $$v \
				-schema-location default -schema-location '$(CRD_SCHEMAS)' || exit 1; \
		done; \
	done

.PHONY: examples
examples: ## Lint the files in examples/ and validate what they render
	@for e in $(EXAMPLES); do \
		args=$$(echo "$$e" | tr '+' '\n' | sed 's|.*|-f examples/&.yaml|' | tr '\n' ' '); \
		echo "==> examples: $$e"; \
		helm lint --strict $(CHART) $$args >/dev/null || { helm lint --strict $(CHART) $$args; exit 1; }; \
		out=$$(helm template $(RELEASE) $(CHART) -n $(NAMESPACE) $$args) || exit 1; \
		printf '%s\n' "$$out" | kubeconform -strict -summary -kubernetes-version $(lastword $(KUBE_VERSIONS)) -schema-location default || exit 1; \
	done

.PHONY: lint-actions
lint-actions: ## Lint the workflows and scripts: actionlint, shellcheck, zizmor (needs uvx)
	actionlint
	shellcheck -S warning $$(git ls-files 'hack/*.sh')
	uvx zizmor@$(ZIZMOR) --config .github/zizmor.yml .github/workflows

.PHONY: template
template: ## Render the chart with default values
	helm template $(RELEASE) $(CHART) -n $(NAMESPACE)

.PHONY: test
test: lint unittest kubeconform examples check-generated check-changes check-versions ## Run every static check

.PHONY: kind-up
kind-up: ## Create a local kind cluster
	kind get clusters | grep -qx $(KIND_CLUSTER) || kind create cluster --name $(KIND_CLUSTER) --config hack/kind-config.yaml --wait 120s

.PHONY: kind-down
kind-down: ## Delete the local kind cluster
	kind delete cluster --name $(KIND_CLUSTER)

.PHONY: install
install: ## Install or upgrade the chart (VALUES: space-separated values files) into a namespace enforcing the restricted Pod Security Standard
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(NAMESPACE) --overwrite pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
	helm upgrade --install $(RELEASE) $(CHART) -n $(NAMESPACE) $(foreach f,$(VALUES),-f $(f)) --wait --timeout 15m

.PHONY: helm-test
helm-test: ## Run helm test against the installed release
	helm test $(RELEASE) -n $(NAMESPACE) --logs

.PHONY: smoke
smoke: ## Run the end-to-end smoke test against the installed release
	hack/smoke.sh $(RELEASE) $(NAMESPACE)
