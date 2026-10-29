# Email, Git and other integrations

Appwrite talks to a few outside services that the chart doesn't run: an SMTP
server for email, a Git host for Git deployments, an SMS provider for phone
sign-in, Sentry for errors. This guide shows how to connect each one.

| Integration | What it's for | Configure with |
| --- | --- | --- |
| [Email](#email-smtp) | verification, password recovery, invitations | `smtp` |
| [Git deployments](#git-deployments) | deploying Functions and Sites from a repository | `_APP_VCS_*` |
| [Console sign-in](#console-sign-in-with-github-gitlab-bitbucket-or-google) | signing in to the console with GitHub, GitLab, Bitbucket or Google | `_APP_CONSOLE_*` |
| [SMS](#sms) | phone sign-in and SMS verification | `_APP_SMS_*` |
| [Error tracking](#error-tracking) | sending server errors to Sentry | `_APP_LOGGING_CONFIG` |
| [Antivirus](storage.md#antivirus) | scanning uploads with ClamAV | `_APP_STORAGE_ANTIVIRUS*` |

Some settings live in the Appwrite console, per project, not in the chart:
sign-in providers for your apps' users (OAuth2), Messaging providers
(Mailgun, SendGrid, Twilio, FCM, APNs and others), and a project's own SMTP
server, which replaces the chart's for that project's emails.

With `networkPolicy.egress.enabled`, Appwrite can only reach these services
once you allow them in `networkPolicy.egress.extraRules`
([security.md](security.md#egress)).

## Passing settings and secrets

Integrations without a dedicated value are set through Appwrite's
environment variables
([reference](https://appwrite.io/docs/advanced/self-hosting/configuration/environment-variables)):

- **`appwrite.config`** for plain settings. They go into the chart's
  ConfigMap.
- **`appwrite.secretConfig`** for secrets you're happy to keep in your values
  file. The chart stores them in a Secret.
- **`appwrite.extraEnvFrom`** for a Secret you manage yourself, created with
  `kubectl`, External Secrets or Sealed Secrets. Name each key after the
  variable. This keeps secrets out of your values entirely.

```yaml
appwrite:
  config:
    _APP_VCS_GITHUB_APP_NAME: my-appwrite
  secretConfig:
    _APP_LOGGING_CONFIG: sentry://...
  extraEnvFrom:
    - secretRef:
        name: appwrite-integrations
```

When a Secret you don't control uses other key names, map a key to a
variable with `appwrite.extraEnv`:

```yaml
appwrite:
  extraEnv:
    - name: _APP_VCS_GITHUB_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: github-app
          key: client-secret
```

All four reach every pod that runs the Appwrite image: API, realtime,
workers, tasks, MQTT and the migration Job.

### Which value wins

From lowest to highest precedence:

1. Appwrite's defaults (`charts/appwrite/files/env-defaults.yaml`), then the
   variables the chart computes from its values (domains, SMTP host,
   database hosts). Both are in the ConfigMap.
2. `appwrite.config`, which replaces keys in the ConfigMap.
3. `appwrite.secretConfig`.
4. `appwrite.extraEnvFrom`, in list order.
5. `appwrite.extraEnv`, and the variables the chart sets on each container.

The ConfigMap already lists the non-secret Git and console sign-in
variables (`_APP_VCS_GITHUB_APP_ID`, `_APP_CONSOLE_GITHUB_APP_ID`, ...) with
empty values. Setting one in any of the places above replaces the empty
default.

The variables the chart sets on each container are of two kinds:

- **Credentials**, such as `_APP_SMTP_PASSWORD`, `_APP_DB_PASS` and
  `_APP_OPENSSL_KEY_V1`. Nothing in steps 2 to 4 overrides them. Set them
  through their own values (`smtp.password`, `database.password`, ...;
  see [credentials](external-databases.md#credentials)).
- **Per-pod sizing**: `_APP_CPU_NUM`, `_APP_WORKERS_NUM`,
  `_APP_WORKER_MAX_COROUTINES`, `_APP_CONNECTIONS_DB_USAGE` and
  `_APP_CONNECTIONS_DB_EXECUTIONS`. The chart leaves one out when `config`
  or `secretConfig` sets it, so those two can override it. A key in
  `extraEnvFrom` can't.

Pods restart on their own when `config` or `secretConfig` changes. After
changing a Secret you manage, restart them:

```console
kubectl -n appwrite rollout restart deployment -l app.kubernetes.io/instance=appwrite
```

## Email (SMTP)

Without SMTP, Appwrite can't send verification emails, password recovery
links, magic URLs or team invitations. Any SMTP server works:

```console
kubectl -n appwrite create secret generic appwrite-smtp \
  --from-literal=smtp-password='<SMTP password or API key>'
```

```yaml
smtp:
  host: email-smtp.eu-west-1.amazonaws.com
  port: 587                          # the default
  secure: tls                        # the default: STARTTLS on 587; use ssl with port 465
  username: <SMTP username>
  password:
    secretName: appwrite-smtp        # or value: ... inline
appwrite:
  system:
    emailName: Example
    emailAddress: noreply@example.com   # a sender your provider lets you use
```

| Provider | `host` | `username` | Password |
| --- | --- | --- | --- |
| Amazon SES | `email-smtp.<region>.amazonaws.com` | SMTP user name from *SMTP settings* (not an IAM access key) | its SMTP password |
| SendGrid | `smtp.sendgrid.net` | `apikey` | an API key |
| Postmark | `smtp.postmarkapp.com` | a server API token | the same token |
| Mailgun | `smtp.mailgun.org` (EU: `smtp.eu.mailgun.org`) | the domain's SMTP login | its SMTP password |
| Resend | `smtp.resend.com` | `resend` | an API key |
| Brevo | `smtp-relay.brevo.com` | your SMTP login | an SMTP key |

All of them accept port 587 with `secure: tls`. The sender address
(`appwrite.system.emailAddress`, `noreply@<domain>` by default) must be on a
domain you've verified with the provider, or it rejects the message.

To check it, invite someone to a team in the console or use *Forgot
password*. When nothing arrives, the log of the worker that sends mail says
why:

```console
kubectl -n appwrite logs deploy/appwrite-worker | grep -i mail
```

| `workers.mode` | Deployment that sends mail |
| --- | --- |
| `combined` (default) | `appwrite-worker` |
| `separate` | `appwrite-worker-mails` |
| `grouped` | `appwrite-worker-<group>`, for the group that lists `mails` |

`Skipped mail processing. No SMTP configuration has been set.` means
`smtp.host` is empty and the project has no SMTP server of its own.

## Git deployments

Functions and Sites can deploy automatically from a Git repository on every
push, and comment on pull requests with preview links. This needs
[Functions and Sites](executor.md) enabled, and Appwrite reachable from the
Git host, which sends webhooks: from the internet for GitHub, gitlab.com and
Bitbucket.

Callback URLs use your console's domain: `appwrite.domain`, unless you set
`appwrite.consoleDomain`. Webhooks go to `appwrite.domain`.

### GitHub

Appwrite connects through a GitHub App that you create and own.

**1. Create the app** under *Settings → Developer settings → GitHub Apps* of
your user or organization:

| Setting | Value |
| --- | --- |
| Callback URLs, in this order | `https://<console domain>/v1/vcs/github/callback`<br>`https://<console domain>/v1/account/sessions/oauth2/callback/github/console` |
| Request user authorization (OAuth) during installation | on |
| Post installation: Redirect on update | on |
| Webhook: Active | on |
| Webhook URL | `https://<domain>/v1/vcs/github/events` |
| Webhook secret | a random string, e.g. `openssl rand -hex 32` |
| Where can this GitHub App be installed? | Any account |

Give it the repository permissions *Administration*, *Checks*, *Commit
statuses*, *Contents*, *Issues*, *Pull requests* and *Webhooks* (read and
write) and *Metadata* (read-only), the account permission *Email addresses*
(read-only), and subscribe it to the *Pull request* and *Push* events.
[Appwrite's guide](https://appwrite.io/docs/advanced/self-hosting/configuration/version-control)
has screenshots of each step.

**2. Collect its credentials** from the app's settings page: the App ID, the
Client ID, a client secret (*Generate a new client secret*), and a private
key (*Generate a private key*, which downloads a `.pem` file).

**3. Give them to Appwrite.** The private key goes in as a file, line breaks
and all:

```console
kubectl -n appwrite create secret generic appwrite-github \
  --from-file=_APP_VCS_GITHUB_PRIVATE_KEY=my-appwrite.2026-10-09.private-key.pem \
  --from-literal=_APP_VCS_GITHUB_CLIENT_SECRET='<client secret>' \
  --from-literal=_APP_VCS_GITHUB_WEBHOOK_SECRET='<webhook secret>'
```

```yaml
appwrite:
  config:
    _APP_VCS_GITHUB_APP_NAME: my-appwrite      # the slug in https://github.com/apps/<slug>
    _APP_VCS_GITHUB_APP_ID: "123456"
    _APP_VCS_GITHUB_CLIENT_ID: Iv23li...
  extraEnvFrom:
    - secretRef:
        name: appwrite-github
```

Upgrade, then open a function or site in the console and choose *Connect
Git*. If GitHub shows a delivery error under the app's *Advanced* tab, check
that `https://<domain>/v1/vcs/github/events` is reachable from outside and
that the webhook secret matches. The secret is required: Appwrite 2.4.0 and later
refuse GitHub's events without `_APP_VCS_GITHUB_WEBHOOK_SECRET`.

### GitLab, Gitea and Bitbucket

These connect through an OAuth application that you create on the Git host.
Give it the redirect URL `https://<console domain>/v1/vcs/<host>/callback`
(`gitlab`, `gitea` or `bitbucket`) and the scopes Appwrite asks for:

| Host | Scopes |
| --- | --- |
| GitLab (gitlab.com or self-hosted) | `api`, `read_user` |
| Gitea | `read:repository`, `write:repository`, `read:organization`, `read:issue`, `write:issue` |
| Bitbucket (bitbucket.org only) | `account`, `repository:write`, `pullrequest:write`, `webhook` |

Then set its variables. Endpoints and client IDs go in `appwrite.config`;
client and webhook secrets in a Secret, as for GitHub. The webhook secret is
a random string you choose. Appwrite registers a webhook with it on each
repository you connect, so all three hosts require one.

| Host | `appwrite.config` | Secret |
| --- | --- | --- |
| GitLab | `_APP_VCS_GITLAB_CLIENT_ID`, plus `_APP_VCS_GITLAB_ENDPOINT` when self-hosted (default `https://gitlab.com`) | `_APP_VCS_GITLAB_CLIENT_SECRET`, `_APP_VCS_GITLAB_WEBHOOK_SECRET` |
| Gitea | `_APP_VCS_GITEA_ENDPOINT`, `_APP_VCS_GITEA_CLIENT_ID` | `_APP_VCS_GITEA_CLIENT_SECRET`, `_APP_VCS_GITEA_WEBHOOK_SECRET` |
| Bitbucket | `_APP_VCS_BITBUCKET_CLIENT_ID` (the OAuth consumer's key) | `_APP_VCS_BITBUCKET_CLIENT_SECRET`, `_APP_VCS_BITBUCKET_WEBHOOK_SECRET` |

The endpoint must be reachable from the Appwrite pods. For GitLab it must
also be reachable from your users' browsers. For Gitea, set
`_APP_VCS_GITEA_BROWSER_ENDPOINT` when browsers reach it on another address,
such as when `_APP_VCS_GITEA_ENDPOINT` is a cluster-internal Service.

Webhooks go to `https://<domain>/v1/vcs/<host>/events`. When the Git host
can't reach that address, for example a Gitea in the same cluster, set
`_APP_VCS_WEBHOOK_URL` to a base URL it can reach, such as
`http://appwrite-api.appwrite.svc`.

### Entire

Appwrite 2.6 adds [Entire](https://entire.io) as a Git provider, through a
plugin you register with Entire. Set `_APP_VCS_ENTIRE_PLUGIN` (the plugin's
slug), `_APP_VCS_ENTIRE_ISSUER` (usually `https://<console domain>`) and, for
a core other than `https://us.auth.entire.io`, `_APP_VCS_ENTIRE_ENDPOINT` in
`appwrite.config`, and the plugin's Ed25519 private key (PKCS#8 PEM) as
`_APP_VCS_ENTIRE_PRIVATE_KEY` in a Secret, as for GitHub. Callbacks go to
`https://<console domain>/v1/vcs/entire/callback` and events to
`https://<domain>/v1/vcs/entire/events`. The console offers Entire next to
the other Git providers from 2.6.2 on; 2.6.1's kept it behind a feature
flag that is off.

## Console sign-in with GitHub, GitLab, Bitbucket or Google

By default, console users sign in with email and password. To offer a
provider as well, create an OAuth application there with the redirect URL
`https://<console domain>/v1/account/sessions/oauth2/callback/<provider>/console`
(`github`, `gitlab`, `bitbucket` or `google`), and set its ID and secret:

| Provider | ID (`appwrite.config`) | Secret |
| --- | --- | --- |
| GitHub | `_APP_CONSOLE_GITHUB_APP_ID` | `_APP_CONSOLE_GITHUB_SECRET` |
| GitLab | `_APP_CONSOLE_GITLAB_APP_ID`, plus `_APP_CONSOLE_GITLAB_ENDPOINT` when self-hosted (default `https://gitlab.com`) | `_APP_CONSOLE_GITLAB_SECRET` |
| Bitbucket | `_APP_CONSOLE_BITBUCKET_APP_ID` | `_APP_CONSOLE_BITBUCKET_SECRET` |
| Google | `_APP_CONSOLE_GOOGLE_APP_ID` | `_APP_CONSOLE_GOOGLE_SECRET` |

`appwrite.console.whitelistRoot`, `whitelistEmails` and `whitelistIPs` still
decide who may create an account.

## SMS

Phone sign-in and SMS verification need an SMS provider. Appwrite reads it
from a DSN, `sms://<user>:<secret>@<provider>`, and sends from
`_APP_SMS_FROM`. Both must be set, or SMS stays off.

```yaml
appwrite:
  config:
    _APP_SMS_FROM: "+15551234567"     # or a Twilio Messaging Service SID (MG...)
  secretConfig:
    _APP_SMS_PROVIDER: sms://<account SID>:<auth token>@twilio
```

| `<provider>` | `<user>` | `<secret>` |
| --- | --- | --- |
| `twilio` | Account SID | Auth token |
| `textmagic` | username | API key |
| `telesign` | customer ID | API key |
| `msg91` | sender ID | auth key |
| `vonage` | API key | API secret |

MSG91 also needs a template ID: add `?templateId=<id>` to the DSN, or
Appwrite uses `_APP_SMS_FROM` as the template ID. URL-encode the user and
secret if they contain anything but letters and digits. Appwrite's
[SMS guide](https://appwrite.io/docs/advanced/self-hosting/configuration/sms)
has more on each provider.

## Error tracking

Appwrite reports server errors to Sentry, from the API, workers, tasks and
realtime. Rewrite your project's Sentry DSN,
`https://<key>@<sentry host>/<project id>`, as:

```yaml
appwrite:
  secretConfig:
    _APP_LOGGING_CONFIG: sentry://<project id>:<key>@<sentry host>/
```

Sentry is the only provider Appwrite 2.6.2 supports. When the DSN is
invalid, the pods log `Invalid _APP_LOGGING_CONFIG, error reporting is
disabled` at start-up. Logs go to stdout regardless, as JSON by default
(`appwrite.logFormat`), ready for your log pipeline.
