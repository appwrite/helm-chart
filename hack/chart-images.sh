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
# parent key (the component), or "appwrite" for the top-level image.
images=$(yq -r '
  [.. | select(tag == "!!map" and has("registry") and has("repository") and has("tag"))
      | {"name": (path | select(length > 1) | .[-2]) // "appwrite", "ref": (.registry + "/" + .repository + ":" + (.tag // ""))}]
  | sort_by(.name) | .[] | "- name: " + .name + "\n  image: " + .ref' "$CHART/values.yaml" \
  | sed "s/:\$/:$app_version/")

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
