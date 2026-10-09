# Email, Git and other integrations

Appwrite talks to a few outside services that the chart doesn't run: an SMTP
server for email, GitHub for Git deployments, an SMS provider for phone
sign-in, Sentry for errors. This guide shows how to connect each one.

| Integration | What it's for | Configure with |
| --- | --- | --- |
| [Email](#email-smtp) | verification, password recovery, invitations | `appwrite.smtp` |
| [Git deployments](#git-deployments) | deploying Functions and Sites from a repository | `_APP_VCS_*` |
| [Console sign-in](#console-sign-in-with-github-gitlab-bitbucket-or-google) | signing in to the console with GitHub, GitLab, Bitbucket or Google | `_APP_CONSOLE_*` |
| [SMS](#sms) | phone sign-in and SMS verification | `_APP_SMS_*` |
| [Error tracking](#error-tracking) | sending server errors to Sentry | `_APP_LOGGING_CONFIG` |
| [Antivirus](storage.md#antivirus) | scanning uploads with ClamAV | `_APP_STORAGE_ANTIVIRUS*` |
| [Assistant](optional-components.md#assistant) | the console's AI assistant (OpenAI) | `assistant` |

Two kinds of settings live in the Appwrite console, per project, not in the
chart: sign-in providers for your apps' users (OAuth2), and Messaging
providers (Mailgun, SendGrid, Twilio, FCM, APNs and others).

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

Later sources win: a key in `extraEnvFrom` overrides the same key in
`secretConfig`, which overrides `config`. Pods restart on their own when
`config` or `secretConfig` changes. After changing a Secret you manage,
restart them:

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
appwrite:
  smtp:
    host: email-smtp.eu-west-1.amazonaws.com
    port: 587
    secure: tls                      # STARTTLS on 587; use ssl with port 465
    username: <SMTP username>
    existingSecret: appwrite-smtp    # or password: ... inline
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
password*. When nothing arrives, the worker's log says why:

```console
kubectl -n appwrite logs deploy/appwrite-worker | grep -i mail
```

With `workers.mode: separate` or `grouped`, look at the Deployment that
consumes the `mails` queue instead.

## Git deployments

Functions and Sites can deploy automatically from a Git repository on every
push, and comment on pull requests with preview links. This needs
[Functions and Sites](executor.md) enabled, and Appwrite reachable from the
internet so the Git host can send webhooks.

### GitHub

Appwrite connects through a GitHub App that you create and own.

**1. Create the app** under *Settings → Developer settings → GitHub Apps* of
your user or organization. Use your console's domain (`appwrite.domain`
unless you set `appwrite.consoleDomain`):

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
that the webhook secret matches.

### GitLab, Gitea and Bitbucket

Appwrite 2.3.0 also reads settings for these, through OAuth applications
instead of an app:

| Host | Variables | Redirect URL |
| --- | --- | --- |
| GitLab (gitlab.com or self-hosted) | `_APP_VCS_GITLAB_ENDPOINT`, `_APP_VCS_GITLAB_CLIENT_ID`, `_APP_VCS_GITLAB_CLIENT_SECRET`, `_APP_VCS_GITLAB_WEBHOOK_SECRET` | `https://<console domain>/v1/vcs/gitlab/callback` |
| Gitea | `_APP_VCS_GITEA_ENDPOINT`, `_APP_VCS_GITEA_CLIENT_ID`, `_APP_VCS_GITEA_CLIENT_SECRET`, `_APP_VCS_GITEA_WEBHOOK_SECRET` | `https://<console domain>/v1/vcs/gitea/callback` |
| Bitbucket | `_APP_VCS_BITBUCKET_CLIENT_ID`, `_APP_VCS_BITBUCKET_CLIENT_SECRET`, `_APP_VCS_BITBUCKET_WEBHOOK_SECRET` | `https://<console domain>/v1/vcs/bitbucket/callback` |

Endpoints and client IDs go in `appwrite.config`; client and webhook secrets
in a Secret, as for GitHub. Appwrite creates the repository webhooks itself.
When the Git host can't reach Appwrite's public domain, set
`_APP_VCS_WEBHOOK_URL` to an address it can reach.

## Console sign-in with GitHub, GitLab, Bitbucket or Google

By default, console users sign in with email and password. To offer a
provider as well, create an OAuth application there with the redirect URL
`https://<console domain>/v1/account/sessions/oauth2/callback/<provider>/console`
(`github`, `gitlab`, `bitbucket` or `google`), and set its ID and secret:

| Provider | ID (`appwrite.config`) | Secret |
| --- | --- | --- |
| GitHub | `_APP_CONSOLE_GITHUB_APP_ID` | `_APP_CONSOLE_GITHUB_SECRET` |
| GitLab | `_APP_CONSOLE_GITLAB_APP_ID`, plus `_APP_CONSOLE_GITLAB_ENDPOINT` when self-hosted | `_APP_CONSOLE_GITLAB_SECRET` |
| Bitbucket | `_APP_CONSOLE_BITBUCKET_APP_ID` | `_APP_CONSOLE_BITBUCKET_SECRET` |
| Google | `_APP_CONSOLE_GOOGLE_APP_ID` | `_APP_CONSOLE_GOOGLE_SECRET` |

`appwrite.console.whitelistRoot` and `whitelistEmails` still decide who may
create an account.

## SMS

Phone sign-in and SMS verification need an SMS provider: Twilio, Textmagic,
Telesign, MSG91 or Vonage.

```yaml
appwrite:
  config:
    _APP_SMS_FROM: "+15551234567"     # or a Twilio Messaging Service SID (MG...)
  secretConfig:
    _APP_SMS_PROVIDER: sms://<account SID>:<auth token>@twilio
```

URL-encode the user and secret if they contain anything but letters and
digits. Appwrite's [SMS guide](https://appwrite.io/docs/advanced/self-hosting/configuration/sms)
lists what each provider expects.

## Error tracking

Appwrite reports server errors to Sentry, from the API, workers, tasks and
realtime:

```yaml
appwrite:
  secretConfig:
    _APP_LOGGING_CONFIG: sentry://<project id>:<key>@<sentry host>/
```

Sentry is the only provider Appwrite 2.3.0 supports. Logs go to stdout
regardless, as JSON by default (`appwrite.logFormat`), ready for your log
pipeline.
