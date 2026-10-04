# Contributing

Thanks for helping improve the Appwrite Helm chart.

## Prerequisites

| Tool | Version |
| --- | --- |
| [Helm](https://helm.sh) | 4.3.x (3.18+ is also supported) |
| [chart-testing](https://github.com/helm/chart-testing) (`ct`) | 3.14.x |
| [helm-docs](https://github.com/norwoodj/helm-docs) | 1.14.x |
| [kubeconform](https://github.com/yannh/kubeconform) | 0.7+ |
| [yamllint](https://github.com/adrienverge/yamllint) | 1.35+ |

Install the Helm plugins with `make tools`. It installs
[helm-unittest](https://github.com/helm-unittest/helm-unittest) and
[helm-values-schema-json](https://github.com/losisin/helm-values-schema-json).

## Workflow

1. Change templates and `values.yaml`. Document every new value with a
   `# --` comment, and add `# @schema` annotations where the inferred type
   isn't enough.
2. Run `make generate` to refresh `values.schema.json` and the chart README.
   Never edit those two files by hand.
3. Add or update unit tests under `charts/appwrite/tests/`.
4. Run `make test`.
5. Bump `version` in `charts/appwrite/Chart.yaml` (SemVer), add an entry to
   `CHANGELOG.md`, and mirror it into the `artifacthub.io/changes` annotation.

Run `make help` to list every target.

## Conventions

- Values are camelCase. Use maps rather than lists so `--set` works.
- Helpers are namespaced `appwrite.*` and called with `include`.
- One Kubernetes resource per template file.
- Pin image tags; never use `latest`.
- Pods must pass the Kubernetes Pod Security Standard `restricted` profile
  unless a component documents why it can't.
