#!/usr/bin/env bash
set -euo pipefail

CHART="charts/knot-resolver/Chart.yaml"
LEVEL="${1:-patch}"

current=$(yq '.version' "$CHART")
next=$(semver -i "$LEVEL" "$current")

yq -i ".version = \"$next\"" "$CHART"

echo "$current -> $next"
