#!/usr/bin/env bash
# Fails when the docs, examples, values, templates or workflows name an
# Appwrite version other than appVersion in charts/appwrite/Chart.yaml, so an
# upgrade can't leave a claim about the old version behind.
#
# It looks at "Appwrite X.Y.Z", the appwrite/appwrite:X.Y.Z image and links
# into the appwrite/appwrite repository at a tag. History is allowed when it
# says so: "Appwrite 2.4.0 and later", "or later", or "Appwrite 2.4.0's ...".
# Not checked: CHANGELOG.md, the version notes in docs/upgrading.md,
# Chart.yaml's annotations, the unit tests (which use made-up versions) and
# generated files.
#
# Usage: hack/check-versions.sh
set -euo pipefail

CHART="${CHART:-charts/appwrite}"
app_version=$(awk '/^appVersion:/ {gsub(/"/, "", $2); print $2}' "$CHART/Chart.yaml")
[[ -n "$app_version" ]] || { echo "No appVersion in $CHART/Chart.yaml" >&2; exit 2; }

v='[0-9]+\.[0-9]+\.[0-9]+'
pattern="Appwrite ${v}('s| and later| or later)?|appwrite/appwrite:${v}|appwrite/appwrite/(blob/|tree/|raw/)?${v}/"

# Prints the line from which a file is history, if it has one: the version
# notes of docs/upgrading.md, and Chart.yaml's annotations (its changes are
# history, and hack/chart-images.sh checks its images).
history_from() {
  case "$1" in
    docs/upgrading.md) grep -n '^## Version notes' "$1" | cut -d: -f1 ;;
    "$CHART/Chart.yaml") grep -n '^annotations:' "$1" | cut -d: -f1 ;;
  esac
}

stale=0
while IFS= read -r file; do
  history=$(history_from "$file" || true)
  while IFS= read -r hit; do
    line=${hit%%:*} match=${hit#*:}
    case "$match" in *"'s" | *" and later" | *" or later") continue ;; esac
    [[ -n "$history" && "$line" -ge "$history" ]] && continue
    [[ "$match" =~ ($v) ]]
    if [[ "${BASH_REMATCH[1]}" != "$app_version" ]]; then
      echo "${file}:${line}: ${match} (the chart ships Appwrite ${app_version})"
      stale=1
    fi
  done < <(grep -noE "$pattern" "$file" || true)
done < <(git ls-files README.md CONTRIBUTING.md RELEASING.md SECURITY.md 'docs/*.md' 'examples/*' \
  "$CHART/Chart.yaml" "$CHART/README.md.gotmpl" "$CHART/values.yaml" "$CHART/templates/*" "$CHART/files/*" \
  '.github/workflows/*' 'hack/*.sh')

if [[ "$stale" -ne 0 ]]; then
  echo >&2
  echo "Update these to Appwrite ${app_version}, or say which versions a claim covers (\"and later\")." >&2
  exit 1
fi
echo "Every Appwrite version named matches appVersion ${app_version}."
