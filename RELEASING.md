# Releasing

Releases are automated: merging a change to `charts/appwrite/Chart.yaml`
with a new `version` into `main` runs [`release.yaml`](.github/workflows/release.yaml),
which:

1. packages the chart and pushes it to `oci://ghcr.io/appwrite/charts/appwrite`;
2. signs it with cosign (keyless, GitHub OIDC);
3. attaches a build provenance attestation;
4. creates a GitHub release `appwrite-<version>` with the changelog entry;
5. pushes `artifacthub-repo.yml` for Artifact Hub.

Versions that are already in the registry are skipped.

## Cutting a release

1. Move the `[Unreleased]` changelog entries under `## [<version>] - <date>`
   and mirror them into `artifacthub.io/changes` in `Chart.yaml`.
2. Bump `version` in `charts/appwrite/Chart.yaml` (SemVer). Bump the minor
   version for new features or a new Appwrite minor, the major version for
   breaking value changes after 1.0.
3. Run `make generate test` and open a PR.
4. Merge. Check the release workflow, then verify:

   ```console
   cosign verify ghcr.io/appwrite/charts/appwrite:<version> \
     --certificate-identity https://github.com/appwrite/helm-chart/.github/workflows/release.yaml@refs/heads/main \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   gh attestation verify oci://ghcr.io/appwrite/charts/appwrite:<version> --repo appwrite/helm-chart
   ```

## Before the first release (0.1.0)

- [ ] Make the repository public, then run the release workflow manually
      (Actions → Release → Run workflow); it skips itself while the repository
      is private. Build provenance attestations on private
      repositories need GitHub Enterprise Cloud, and keyless signatures record
      the repository in the public Rekor transparency log anyway.
- [ ] After the first push, make the `charts/appwrite` package public in the
      GHCR package settings, and link it to this repository.
- [ ] Register the repository on Artifact Hub (kind: Helm charts, URL
      `oci://ghcr.io/appwrite/charts/appwrite`), then add its
      `repositoryID` and an owner to `artifacthub-repo.yml`.
- [ ] Set `check-version-increment: true` in `ct.yaml`, so every later PR that
      changes the chart bumps its version.
- [ ] Enable the Renovate GitHub app for the repository.
