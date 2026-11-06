#!/usr/bin/env bash
# Keeps the artifacthub.io/images annotation in Chart.yaml in sync with the
# images in values.yaml.
#
# Usage: hack/chart-images.sh [--check]
# Requires: yq v4.
set -euo pipefail

CHART="${CHART:-charts/appwrite}"
app_version=$(yq '.appVersion' "$CHART/Chart.yaml")

# Every map with registry, repository and tag is an image; name it after its
# parent key (the component), "<datastore>-exporter" for a metrics exporter,
# or "appwrite" for the top-level image. "builtin" is skipped so that
# database.builtin.image is "database", not "builtin".
images=$(yq -r '
  [.. | select(tag == "!!map" and has("registry") and has("repository") and has("tag"))
      | {"name": (path | map(select(. != "builtin")) | select(length > 1) | (select(.[-2] == "metrics") | .[-3] + "-exporter") // .[-2]) // "appwrite", "ref": (.registry + "/" + .repository + ":" + (.tag // ""))}]
  | sort_by(.name) | .[] | "- name: " + .name + "\n  image: " + .ref' "$CHART/values.yaml" \
  | sed "s/:\$/:$app_version/")

# The security scan uploads each image's results under a category made from
# its name; two images with one name overwrite each other's results.
dups=$(echo "$images" | sed -n 's/^- name: //p' | sort | uniq -d)
if [[ -n "$dups" ]]; then
  echo "Image names in $CHART/values.yaml aren't unique:" $dups
  exit 1
fi

if [[ "${1:-}" == --check ]]; then
  current=$(yq -r '.annotations["artifacthub.io/images"]' "$CHART/Chart.yaml")
  if [[ "$(echo "$current" | sed '/^$/d')" != "$(echo "$images" | sed '/^$/d')" ]]; then
    echo "artifacthub.io/images in $CHART/Chart.yaml is out of date: run hack/chart-images.sh"
    diff <(echo "$current") <(echo "$images") || true
    exit 1
  fi
  exit 0
fi

IMAGES="$images" yq -i '.annotations["artifacthub.io/images"] = strenv(IMAGES) + "\n" | .annotations["artifacthub.io/images"] style="literal"' "$CHART/Chart.yaml"
