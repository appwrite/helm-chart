# Appwrite Helm chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.3.0](https://img.shields.io/badge/AppVersion-2.3.0-informational?style=flat-square)

Appwrite, the open-source backend platform, on Kubernetes. Deploys the API, console, realtime, workers and schedulers with optional built-in PostgreSQL, Redis and ClickHouse.

> [!WARNING]
> This chart is under active development and not yet released. Values and
> behaviour may change between pre-1.0 versions.

## Requirements

- Kubernetes >=1.29.0-0
- Helm 4.x, or Helm 3.18+

## Installing

```console
helm install appwrite oci://ghcr.io/levivannoort/charts/appwrite \
  --namespace appwrite --create-namespace
```

## Uninstalling

```console
helm uninstall appwrite --namespace appwrite
```

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| levivannoort |  | <https://github.com/levivannoort> |

## Source Code

* <https://github.com/levivannoort/helm-chart>
* <https://github.com/appwrite/appwrite>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonAnnotations | object | `{}` | Annotations added to every resource rendered by the chart. |
| commonLabels | object | `{}` | Labels added to every resource rendered by the chart. |
| fullnameOverride | string | `""` | Override the fully qualified app name used in resource names. |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| serviceAccount.annotations | object | `{}` | Annotations for the ServiceAccount (e.g. workload identity bindings). |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the ServiceAccount token. Appwrite does not talk to the Kubernetes API. |
| serviceAccount.create | bool | `true` | Create a ServiceAccount for Appwrite pods. |
| serviceAccount.name | string | `""` | Name of the ServiceAccount. Defaults to the fullname when `create` is true, `default` otherwise. |

## License

BSD 3-Clause. See [LICENSE](https://github.com/levivannoort/helm-chart/blob/main/LICENSE).
