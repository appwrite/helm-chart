# Appwrite Helm chart

A Helm chart for running [Appwrite](https://appwrite.io), the open-source
backend platform, on Kubernetes.

> [!WARNING]
> Work in progress. The chart hasn't been released yet.

| | |
| --- | --- |
| Chart | [`charts/appwrite`](charts/appwrite) |
| Appwrite version | 2.3.0 |
| Kubernetes | 1.29+ |
| Helm | 4.x, or 3.18+ |

## What's in this repository

```text
charts/appwrite/   the chart (values, templates, unit tests, CI scenarios)
docs/              operator guides
hack/              scripts used by CI and local development
```

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). Common tasks:

```console
make tools      # install helm-unittest and helm-values-schema-json
make test       # lint, unit tests, kubeconform, generated-file check
make generate   # regenerate values.schema.json and the chart README
```

## License

[BSD 3-Clause](LICENSE).
