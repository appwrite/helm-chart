# Contributing

Thanks for helping improve the Appwrite Helm chart.

## Prerequisites

| Tool | Version | Used by |
| --- | --- | --- |
| [Helm](https://helm.sh) | 4.3.x | everything |
| [chart-testing](https://github.com/helm/chart-testing) (`ct`) | 3.14.x | `make lint` |
| [helm-docs](https://github.com/norwoodj/helm-docs) | 1.14.x | `make docs` |
| [kubeconform](https://github.com/yannh/kubeconform) | 0.7+ | `make kubeconform` |
| [yamllint](https://github.com/adrienverge/yamllint) | 1.35+ | `ct lint` |
| [yq](https://github.com/mikefarah/yq) | 4.x (the Go one) | `make images` |
| Python | 3 | `make schema` |
| PHP | 8+ | `make env-defaults` |
| [kind](https://kind.sigs.k8s.io), `kubectl` | recent | `make kind-up install` |

Install the Helm plugins with `make tools`. It installs
[helm-unittest](https://github.com/helm-unittest/helm-unittest) and
[helm-values-schema-json](https://github.com/losisin/helm-values-schema-json).

The chart itself supports Helm 3.18 and later, and CI lints it with Helm 3
too. Developing needs Helm 4: `make tools` passes `--verify=false`, which
Helm 3's `helm plugin install` doesn't accept. With Helm 3, install the two
plugins by hand without that flag.

## Workflow

1. Change templates and `values.yaml`. Document every new value with a
   `# --` comment, and add `# @schema` annotations where the inferred type
   isn't enough.
2. Run `make generate` to refresh `values.schema.json` and the chart README.
   Never edit those two files by hand.
3. Add or update unit tests under `charts/appwrite/tests/`.
4. Run `make test`.
5. Add an entry under `[Unreleased]` in `CHANGELOG.md`. Releases are cut as
   described in [RELEASING.md](RELEASING.md).

Run `make help` to list every target.

## Moving to a new Appwrite version

The [upstream drift](.github/workflows/upstream-drift.yaml) workflow opens an
issue every week when Appwrite has released a version the chart doesn't ship
yet, listing the environment variables that changed. To follow it:

1. Set `appVersion` in `charts/appwrite/Chart.yaml` and `image.tag` in
   `values.yaml`.
2. Run `make env-defaults` to regenerate `files/env-defaults.yaml` from the
   new version's `app/config/variables.php`, and review the diff. New
   variables may need values or computed settings in `templates/_env.tpl`.
3. Compare the new version's `docker-compose.yml` with the chart: image tags
   of the console, geo, assistant, browser and other components, the
   orchestrator and executor versions, new workers or queues
   (`app/config/workers.php`), and new tasks.
4. Check whether the data migration changed (`src/Appwrite/Migration/Migration.php`)
   and update [docs/upgrading.md](docs/upgrading.md) if it did.
5. Run `make generate test`, then the kind install including the upgrade
   scenario, and add a CHANGELOG entry.

## Conventions

- Values are camelCase. Prefer maps to lists for things users add to or
  override one entry at a time (queues, groups, annotations), so `--set` and
  values merging work. Kubernetes fields that are lists (tolerations,
  `parentRefs`, NetworkPolicy rules) stay lists.
- Helpers are namespaced `appwrite.*` and called with `include`.
- One Kubernetes resource per template file, except where resources only make
  sense together (the orchestrator's ServiceAccount, Role and RoleBinding).
- Pin image tags; never use `latest`.
- Pods must pass the Kubernetes Pod Security Standard `restricted` profile
  unless a component documents why it can't.
