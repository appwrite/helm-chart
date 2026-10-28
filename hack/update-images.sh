#!/usr/bin/env bash
# Updates every pinned image tag in values.yaml to the newest tag in its
# registry, then syncs the artifacthub.io/images annotation.
#
# A candidate tag has the same shape as the current one: the same prefix and
# suffix (v0.20.1, 7.4.7-alpine, 29.9.0-dind, 1.1.159-self-hosted) and the
# same number of version components, so floating tags (7, 7.4, latest) and
# pre-releases (-rc.1) are never picked. The built-in datastores stay on their
# current major version, as in renovate.json, and ClickHouse on its current
# year.month release (26.4.x), since each of those is a feature release.
#
# The images Renovate groups with Appwrite in renovate.json (the console,
# executor, orchestrator and Appwrite's own services) are pinned to what
# Appwrite's docker-compose.yml uses for appVersion, not to the newest tag:
# they're skipped unless --all is given. The Appwrite image follows appVersion
# (its tag is empty) and isn't touched; see CONTRIBUTING.md.
#
# Usage: hack/update-images.sh [--dry-run] [--all]
# Requires: yq v4, jq, curl.
set -euo pipefail

CHART="${CHART:-charts/appwrite}"
VALUES="$CHART/values.yaml"
dry_run=false
all=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --all) all=true ;;
    -h | --help)
      sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg (see --help)" >&2
      exit 2
      ;;
  esac
done
appwrite_group=$(jq -r '.packageRules[] | select(.groupName == "appwrite") | .matchPackageNames[]' \
  "$(dirname "$0")/../renovate.json")

# Prints every tag of registry/repository, using an anonymous pull token when
# the registry asks for one and following Link pagination.
list_tags() {
  local registry=$1 repository=$2 host=$1 auth=() challenge realm service token url
  [[ "$registry" == docker.io ]] && host="registry-1.docker.io"
  url="https://${host}/v2/${repository}/tags/list?n=10000"
  challenge=$(curl -sS -o /dev/null -D - "$url" | tr -d '\r' | grep -i '^www-authenticate: bearer' || true)
  if [[ -n "$challenge" ]]; then
    realm=$(sed -E 's/.*realm="([^"]+)".*/\1/' <<<"$challenge")
    service=$(sed -E 's/.*service="([^"]+)".*/\1/' <<<"$challenge")
    token=$(curl -fsS "${realm}?service=${service}&scope=repository:${repository}:pull" | jq -er '.token // .access_token')
    auth=(-H "Authorization: Bearer ${token}")
  fi
  while [[ -n "$url" ]]; do
    headers=$(mktemp)
    curl -fsS ${auth[@]+"${auth[@]}"} -D "$headers" "$url" | jq -r '.tags[]?'
    url=$(tr -d '\r' < "$headers" | sed -nE 's/^[Ll]ink: <([^>]+)>.*/\1/p')
    rm -f "$headers"
    [[ -z "$url" || "$url" == http* ]] || url="https://${host}${url}"
  done
}

# Prints the newest tag of the same shape as $1 among the tags on stdin,
# keeping its first $2 version components (0: any version, 1: same major).
newest() {
  local current=$1 fixed=$2 prefix suffix pattern="" i=0 part
  [[ "$current" =~ ^([^0-9]*)([0-9]+(\.[0-9]+)*)(.*)$ ]] || return 0
  prefix=${BASH_REMATCH[1]} suffix=${BASH_REMATCH[4]}
  for part in ${BASH_REMATCH[2]//./ }; do
    [[ "$i" -lt "$fixed" ]] || part='[0-9]+'
    pattern+="${pattern:+\\.}${part}"
    i=$((i + 1))
  done
  { grep -E "^$(escape "$prefix")${pattern}$(escape "$suffix")\$" || true; } \
    | awk -v p="${#prefix}" -v s="${#suffix}" '{print substr($0, p + 1, length($0) - p - s) "\t" $0}' \
    | sort -V | tail -1 | cut -f2
}

escape() { sed 's/[][\.*^$+?(){}|/]/\\&/g' <<<"$1"; }

# Read before the loop rather than through process substitution, whose exit
# status set -e doesn't see: a values.yaml yq can't parse must fail the run.
images=$(yq -r '.. | select(tag == "!!map" and has("registry") and has("repository") and .tag != "")
  | [(path | map(tostring) | join(".")), .registry, .repository, .tag] | @tsv' "$VALUES")

changed=0
while IFS=$'\t' read -r path registry repository tag; do
  [[ -n "$path" ]] || continue # the here-string's line when there are no images
  if [[ "$all" == false ]] && grep -qx "${registry}/${repository}" <<<"$appwrite_group"; then
    printf '  %-45s %s (follows Appwrite %s, --all to update)\n' "${registry}/${repository}" "$tag" \
      "$(yq '.appVersion' "$CHART/Chart.yaml")"
    continue
  fi
  fixed=0
  [[ "$path" == *.builtin.image ]] && fixed=1
  [[ "$repository" == clickhouse/clickhouse-server ]] && fixed=2
  latest=$(list_tags "$registry" "$repository" | newest "$tag" "$fixed")
  if [[ -z "$latest" || "$latest" == "$tag" ]]; then
    printf '  %-45s %s\n' "${registry}/${repository}" "$tag"
    continue
  fi
  printf '* %-45s %s -> %s\n' "${registry}/${repository}" "$tag" "$latest"
  changed=$((changed + 1))
  if [[ "$dry_run" == false ]]; then
    # yq -i would drop the file's blank lines: edit only the tag's line, the
    # first one after the image's repository. A quoted tag ("4.48") stays
    # quoted, so YAML doesn't read the new one as a number.
    awk -v repo="$repository" -v old="$tag" -v new="$latest" '
      $1 == "repository:" && $2 == repo { found = 1 }
      found && $1 == "tag:" {
        quote = ($2 ~ /^".*"$/) ? "\"" : ""
        if ($2 == quote old quote) { sub(/tag: .*/, "tag: " quote new quote); found = 0 }
      }
      { print }
    ' "$VALUES" > "$VALUES.tmp" && mv "$VALUES.tmp" "$VALUES"
  fi
done <<<"$images"

if [[ "$changed" -gt 0 && "$dry_run" == false ]]; then
  "$(dirname "$0")/chart-images.sh"
  echo "Updated ${changed} image(s). Run 'make generate test', and add a CHANGELOG.md entry."
fi
