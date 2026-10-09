# Example values

Values files to copy and adapt. Each starts with a comment saying what it
needs and how to install it. CI renders every one of them (`make examples`),
so they stay in step with the chart.

| File | Use it for |
| --- | --- |
| [`local.yaml`](local.yaml) | Trying Appwrite on kind, k3d or Rancher Desktop over plain HTTP |
| [`minimal.yaml`](minimal.yaml) | A first install on a real cluster: your domain, HTTPS through cert-manager, built-in datastores |
| [`production.yaml`](production.yaml) | Managed datastores, S3, Secrets you manage, replicas, grouped workers, NetworkPolicies |

These are overlays, meant to go on top of `minimal.yaml` or
`production.yaml`:

| File | Adds |
| --- | --- |
| [`external-services.yaml`](external-services.yaml) | Your own PostgreSQL, Redis, ClickHouse, S3 and SMTP, each block annotated |
| [`aws.yaml`](aws.yaml) | RDS, ElastiCache, S3, SES, EFS and ClickHouse Cloud, with the AWS-side setup |
| [`functions.yaml`](functions.yaml) | Functions and Sites: S3, the in-cluster executor and wildcard previews |

Helm merges files given with `-f` from left to right, so later files win:

```console
helm install appwrite oci://ghcr.io/appwrite/charts/appwrite \
  --namespace appwrite --create-namespace \
  -f minimal.yaml -f external-services.yaml \
  --wait --timeout 15m
```

To download one without cloning the repository:

```console
curl -fsSLO https://raw.githubusercontent.com/appwrite/helm-chart/main/examples/minimal.yaml
```

Every value is listed in the [chart README](../charts/appwrite/README.md#values),
and `helm show values oci://ghcr.io/appwrite/charts/appwrite` prints the
defaults with their comments.
