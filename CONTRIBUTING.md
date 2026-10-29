# Contributing

Thanks for helping improve the Appwrite Helm chart.

## Prerequisites

| Tool | Version | Used by |
| --- | --- | --- |
| [Helm](https://helm.sh) | 4.3.x | everything |
| [chart-testing](https://github.com/helm/chart-testing) (`ct`) | 3.14.x | `make lint` |
| [yamllint](https://github.com/adrienverge/yamllint) | 1.35+ | `ct lint` |
| [helm-docs](https://github.com/norwoodj/helm-docs) | 1.14.x | `make docs` |
| [kubeconform](https://github.com/yannh/kubeconform) | 0.8.x | `make kubeconform`, `make examples` |
| [yq](https://github.com/mikefarah/yq) | 4.x (the Go one) | `make images` |
| Python | 3 | `make schema` |
| PHP | 8+ | `make env-defaults` |
| [kind](https://kind.sigs.k8s.io), Docker, `kubectl` | recent | `make kind-up install` |
| `curl`, [jq](https://jqlang.org) | recent | `make smoke`, `make changes`, `hack/*.sh` |
| [actionlint](https://github.com/rhysd/actionlint), [shellcheck](https://www.shellcheck.net), [uv](https://docs.astral.sh/uv/) | recent | `make lint-actions` (only when you change workflows or `hack/`) |

Install the Helm plugins with `make tools`. It installs
[helm-unittest](https://github.com/helm-unittest/helm-unittest) and
[helm-values-schema-json](https://github.com/losisin/helm-values-schema-json)
at the versions pinned in the Makefile.

The chart itself supports Helm 3.18 and later, and CI lints and unit-tests it
with Helm 3 too. Developing needs Helm 4: `make tools` passes
`--verify=false`, which Helm 3's `helm plugin install` doesn't accept. With
Helm 3, install the plugins from git instead:

```console
helm plugin install https://github.com/helm-unittest/helm-unittest --version v1.2.1
helm plugin install https://github.com/losisin/helm-values-schema-json --version v2.6.0
```

Run `make help` to list every target.

## Workflow

1. Change the templates and `charts/appwrite/values.yaml`, following the
   [values design](#values-design). Document every new value with a `# --`
   comment directly above it (helm-docs turns these into the chart README),
   and add `# @schema` annotations where the inferred type isn't enough.
2. Add or update unit tests under `charts/appwrite/tests/`, and run them with
   `make unittest`.
3. Keep the guides and examples in step. When a change affects how people
   configure the chart, update the guide in `docs/` and the files in
   `examples/` that set those values. `make examples` lints every example
   and validates what it renders. A new example file goes in `EXAMPLES` in
   the Makefile (an overlay together with its base files, joined with `+`,
   e.g. `minimal+aws`) and in the table in [examples/README.md](examples/README.md).
4. Run `make generate`. It refreshes `values.schema.json`, the chart
   `README.md` and the `artifacthub.io/images` annotation in `Chart.yaml`.
   Never edit those by hand: the chart README comes from `README.md.gotmpl`
   and the comments in `values.yaml`.
5. Run `make test`: lint, unit tests, kubeconform, examples and a check that
   the generated files are current. CI runs the same checks.
6. For changes to what gets deployed, install the chart on kind (see
   [below](#installing-on-kind)).
7. Add an entry under `[Unreleased]` in `CHANGELOG.md`, under the Keep a
   Changelog heading that fits (Added, Changed, Deprecated, Removed, Fixed,
   Security), one bullet per change. Don't bump `version` in `Chart.yaml` or
   edit `artifacthub.io/changes`: both happen when a release is cut, as
   described in [RELEASING.md](RELEASING.md). CI fails a pull request that
   changes `charts/appwrite/` without a changelog entry; a maintainer adds
   the `skip-changelog` label when users won't notice the change (tests,
   comments, CI).
8. Open a pull request against `main` and fill in the checklist.

## Installing on kind

`make install` installs or upgrades the release `appwrite` in the namespace
`appwrite`, labelled to enforce the `restricted` Pod Security Standard, with
the values files in `VALUES` (default `charts/appwrite/ci/default-values.yaml`):

```console
make kind-up                         # kind cluster "appwrite"
make install helm-test smoke         # install, run helm test and hack/smoke.sh
make install VALUES="charts/appwrite/ci/default-values.yaml my-values.yaml"
make kind-down
```

Functions and Sites are on by default, on the built-in object storage. To
build and execute a function as the nightly workflow does:

```console
make install VALUES=charts/appwrite/ci/full-values.yaml
hack/functions-smoke.sh appwrite appwrite node-22
```

The scenarios CI installs are the `charts/appwrite/ci/*-values.yaml` files.

## What CI runs

| Workflow | When | What |
| --- | --- | --- |
| [Lint and test](.github/workflows/lint.yaml) | every pull request and push to `main` | `ct lint` and `helm lint --strict` for every `ci/` scenario, unit tests (Helm 3.18 and 4.3), kubeconform, `make examples`, generated files, `artifacthub.io/images`, Appwrite versions named in the docs (`make check-versions`), `ah lint`, a `CHANGELOG.md` entry for chart changes and `make check-changes` |
| [Install](.github/workflows/test-install.yaml) | changes to `charts/`, `hack/`, the `Makefile` or the workflow | installs on kind per scenario, `helm test`, `hack/smoke.sh`, routes through Traefik, an upgrade from the newest published chart, and a second upgrade that must keep credentials and pods; `Install result` sums up the scenarios |
| [Workflow lint](.github/workflows/actions-lint.yaml) | changes to workflows or `hack/*.sh` | actionlint, shellcheck and zizmor (`make lint-actions` locally) |
| [Renovate generate](.github/workflows/renovate-generate.yaml) | Renovate pull requests that change `values.yaml` or `Chart.yaml` | runs `make generate` and commits the result, see [below](#renovate-pull-requests) |
| [Nightly end-to-end](.github/workflows/e2e-nightly.yaml) | daily | `ci/full-values.yaml` (every optional component but embedding) with Functions built and executed in the cluster |
| [Security scan](.github/workflows/security-scan.yaml) | daily | Trivy on every image in `artifacthub.io/images` and on the manifests of every `ci/` scenario; code scanning once the repository is public |
| [Scorecard](.github/workflows/scorecard.yaml) | weekly and pushes to `main` | OpenSSF Scorecard, once the repository is public |
| [Upstream drift](.github/workflows/upstream-drift.yaml) | weekly | opens an issue when Appwrite releases a version the chart doesn't ship |
| [Release](.github/workflows/release.yaml) | `Chart.yaml` changes on `main` | see [RELEASING.md](RELEASING.md) |

Jobs run on Appwrite's [gcrunner](https://github.com/appwrite-labs/gcrunner)
runners: an ephemeral Compute Engine VM per job, picked with
`runs-on: gcrunner=<run id>-<job>-<index>/machine=<type>` (c3d-standard-8
for the nightly, c3d-standard-4 otherwise). Pull requests from forks ask for
GitHub-hosted runners instead. That isn't a security boundary: a pull request
runs its own copy of the workflow, so a fork can ask for gcrunner, and
gcrunner doesn't check where a job comes from. While the repository is
public, the guard is that a maintainer approves every workflow run from a
fork pull request (Settings → Actions → General → "Require approval for all
external contributors") after reading its workflow changes; never approve a
fork's run that changes `runs-on`. Release and Scorecard stay on GitHub-hosted
runners: Scorecard only publishes results from them, and the release's
signature and provenance attestation name the runner that built the chart.

Workflows pin every action to a commit SHA (with the version in a comment)
and every tool to a version in `env:`, which Renovate updates through the
custom managers in `renovate.json`. A new pinned tool needs a manager there.
Accepted zizmor findings go in `.github/zizmor.yml`, each with its reason.

### Renovate pull requests

Renovate bumps image tags but can't run `make generate`, so the
[Renovate generate](.github/workflows/renovate-generate.yaml) workflow
regenerates the schema, the chart README and `artifacthub.io/images` on its
pull requests and commits them to the branch. It commits with a GitHub App,
because commits pushed with the workflow's own token don't trigger the
checks again. One-time setup, by an organisation owner:

1. Create a GitHub App (Organisation settings → Developer settings → GitHub
   Apps) with no webhook and one repository permission, **Contents: Read and
   write**. Install it on this repository only.
2. Generate a private key for it.
3. In the repository's Actions secrets, set `RENOVATE_HOOK_APP_ID` to the
   App's client ID (its numeric app ID works too) and
   `RENOVATE_HOOK_PRIVATE_KEY` to the private key.

Until then the workflow only leaves a notice, and someone runs
`make generate` on the branch and pushes the result.

## Moving to a new Appwrite version

The [upstream drift](.github/workflows/upstream-drift.yaml) workflow opens an
issue when Appwrite has released a version the chart doesn't ship yet,
listing the environment variables that changed (Renovate, once enabled,
also opens a pull request for `appVersion`). To follow it:

1. Set `appVersion` in `charts/appwrite/Chart.yaml`. Leave `image.tag` in
   `values.yaml` empty: it follows `appVersion`.
2. Run `make env-defaults` to regenerate `files/env-defaults.yaml` from the
   new version's `app/config/variables.php`, and review the diff. New
   variables may need values or computed settings in `templates/_env.tpl`.
3. Compare the new version's `docker-compose.yml` with the chart: image tags
   of the console, geo, browser and other components, the
   orchestrator and executor versions, new workers or queues
   (`app/config/workers.php`, mirrored by the queue catalog in
   `templates/workers/_workers.tpl` and by `workers.queues`), and new tasks.
4. Check whether the data migration changed (`src/Appwrite/Migration/Migration.php`)
   and update [docs/upgrading.md](docs/upgrading.md) if it did.
5. Run `make check-versions`. It lists the docs, examples, values and the
   chart icon URL that still name the old version. Recheck each claim against
   the new version and update it, or write "Appwrite X.Y.Z and later" when
   it's about the version that introduced something. The workflows need
   nothing: they read `appVersion`, and the upgrade test starts from the
   newest published chart.
6. Run `make generate test`, then test the upgrade on kind the way CI does:

   ```console
   make kind-up
   helm upgrade --install appwrite charts/appwrite -n appwrite --create-namespace \
     -f charts/appwrite/ci/default-values.yaml --set image.tag=<old version> --wait --timeout 15m
   make install helm-test smoke
   ```

7. Add a CHANGELOG entry.

## Running Appwrite's own end-to-end tests

[`hack/appwrite-e2e.sh`](hack/appwrite-e2e.sh) runs the PHPUnit e2e suites of
a checkout of [appwrite/appwrite](https://github.com/appwrite/appwrite)
against a release, at the release's Appwrite version:

```console
make kind-up install VALUES="charts/appwrite/ci/full-values.yaml <compute values>"
hack/appwrite-e2e.sh ~/source/appwrite appwrite appwrite tests/e2e/Services/Account
hack/appwrite-e2e.sh ~/source/appwrite appwrite appwrite --filter testCreateUser tests/e2e/Services/Users
```

It reconfigures the release for testing (development mode, open console
sign-up, mail and request catchers), so only point it at a throwaway install.
Functions and Sites suites need the runtimes they use in
`compute.functionsRuntimes` (as `charts/appwrite/ci/full-values.yaml` sets). Suites that need a fresh instance (the first
organization in Teams), GitHub or Gitea, or ClamAV don't pass against a shared
install.

## Values design

- One top-level block per service. A datastore the chart can either run or
  connect to (`database`, `redis`, `clickhouse`) has a `mode`: `builtin`
  deploys it in the release, `external` connects to the user's own.
  Settings Appwrite needs either way (name, username, password, pool sizes)
  sit at the top of the block; `external` holds only the address (`host` and
  `port`, or `url`); `builtin` holds everything about the StatefulSet the
  chart runs (image, resources, persistence, security contexts, scheduling,
  metrics). New built-in settings go under `builtin`. Templates get
  connection settings from `appwrite.db`, `appwrite.redis` and
  `appwrite.clickhouse` in `templates/_datastores.tpl` instead of branching
  on `mode` themselves. Services Appwrite only connects to (`documentsDb`,
  `vectorsDb`, `storage`, `smtp`) are top-level blocks too, not nested under
  `appwrite`.
- Every credential has the same shape, `{value, secretName, secretKey}`:
  `value` is set inline and stored in the chart's Secret (or generated there
  when the chart runs the service and it's empty), `secretName` names a
  Secret the user manages and takes precedence over `value`, and `secretKey`
  is the key in that Secret, defaulting to the key the chart uses in its own
  (`db-password`, `smtp-password`, `s3-access-key`). Templates read one with
  `appwrite.credential` or `appwrite.credential.valueFrom`. A new credential
  goes in the list in `templates/_secrets.tpl` and in the `secretKey` check
  in `templates/_validate.tpl`. The core and compute secrets
  (`appwrite.secrets`, `compute.secrets`) keep their `existingSecret`: each
  is a set of keys in one Secret.
- Components take `extraEnv`, `extraEnvFrom`, `extraVolumes`,
  `extraVolumeMounts`, `extraInitContainers` and `extraContainers` where
  they make sense, so users can add what the chart doesn't model without
  forking it. Name new hooks the same way.
- Scheduling and pod settings live in `defaults.*` and apply to every
  component; a component's own non-empty value replaces the default (pod
  annotations and labels are merged over it). A new per-component setting
  that also makes sense chart-wide goes in `defaults` too and falls back to
  it through the existing helpers.
- Every value has a `# --` comment directly above it, written for the chart
  README: what it does, what empty means, and the Appwrite variable it sets
  if there is one.
- `values.schema.json` is generated with `noAdditionalProperties`, so typos
  fail. Add `# @schema` annotations for enums, minimums, item types and
  maps (`additionalProperties`), and list Kubernetes passthrough fields in
  `hack/schema-postprocess.py` so they accept anything the API does.

## Deprecating a value

Renaming or removing a value breaks existing values files, so do it in
steps that tell users what to change:

1. Keep the old key working, or at least recognised, for at least one minor
   release. The schema rejects unknown keys, so keep a permissive stub for
   the old key in `values.schema.json` (through `values.yaml` or
   `hack/schema-postprocess.py`, never by hand) so the render gets as far
   as the message below.
2. Add the old key to `appwrite.deprecations.renamed` in
   `templates/_deprecations.tpl` with what to do instead (for a rename,
   "renamed to `new.key`"), so setting it fails with the old key and that
   message instead of a generic schema error. Add a unit test that sets the
   old key.
3. Add a `### Deprecated` entry to `CHANGELOG.md` when the old key stops
   being the documented one, and a `### Removed` entry in the release that
   drops the stub and the message.
4. Add a note for the version to "Version notes" in
   [docs/upgrading.md](docs/upgrading.md): the old key, the new one, and an
   example of the change to a values file.

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
