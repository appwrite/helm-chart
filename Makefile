# Developer entry points. Tool versions are pinned here and in CI so local
# runs and CI behave the same.
CHART            ?= charts/appwrite
RELEASE          ?= appwrite
NAMESPACE        ?= appwrite
KUBE_VERSIONS    ?= 1.29.0 1.32.0 1.35.0
HELM_UNITTEST    ?= v1.2.1
HELM_SCHEMA      ?= v2.6.0
CRD_SCHEMAS      ?= https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

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

.PHONY: docs
docs: ## Regenerate the chart README with helm-docs
	helm-docs --chart-search-root charts --template-files README.md.gotmpl

.PHONY: generate
generate: schema docs ## Regenerate all generated files

.PHONY: check-generated
check-generated: generate ## Fail if generated files are out of date
	@git diff --exit-code -- $(CHART)/values.schema.json $(CHART)/README.md \
		|| (echo "Generated files are stale: run 'make generate' and commit the result." && exit 1)

.PHONY: kubeconform
kubeconform: ## Validate rendered manifests against several Kubernetes versions
	@for f in $(CHART)/ci/*-values.yaml; do \
		for v in $(KUBE_VERSIONS); do \
			echo "==> kubeconform $$f (k8s $$v)"; \
			helm template $(RELEASE) $(CHART) -n $(NAMESPACE) -f $$f --kube-version $$v \
				| kubeconform -strict -summary -kubernetes-version $$v \
					-schema-location default -schema-location '$(CRD_SCHEMAS)' || exit 1; \
		done; \
	done

.PHONY: template
template: ## Render the chart with default values
	helm template $(RELEASE) $(CHART) -n $(NAMESPACE)

.PHONY: test
test: lint unittest kubeconform check-generated ## Run every static check
