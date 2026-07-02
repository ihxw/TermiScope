#!/usr/bin/env bash
# Desensitize TermiScope README screenshots (ImageMagick).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG_DIR="$ROOT/images"

redact_light() {
  local src=$1 dst=$2
  shift 2
  convert "$src" -fill '#D8D8D8' "$@" "$dst"
}

redact_dark() {
  local src=$1 dst=$2
  shift 2
  convert "$src" -fill '#1E1E1E' "$@" "$dst"
}

backup_if_needed() {
  local f=$1
  if [[ ! -f "${f%.png}.orig.png" ]]; then
    cp "$f" "${f%.png}.orig.png"
  fi
}

redact_image_1() {
  local src=$1 dst=$2
  local draws=()
  local cols=(10 930 1850 2770 3690)
  local title_rows=(195 1010 1825)
  local bill_rows=(920 1750)

  for row in "${title_rows[@]}"; do
    for col in "${cols[@]}"; do
      draws+=("-draw" "rectangle ${col},${row} $((col + 910)),$((row + 72))")
    done
  done

  for row in "${bill_rows[@]}"; do
    for col in "${cols[@]}"; do
      draws+=("-draw" "rectangle ${col},${row} $((col + 910)),$((row + 88))")
    done
  done

  # Usage quota reset dates between cards
  for row in 850 1865; do
    for col in "${cols[@]}"; do
      draws+=("-draw" "rectangle ${col},${row} $((col + 910)),$((row + 55))")
    done
  done

  draws+=("-draw" "rectangle 3980,12 4580,78")

  redact_light "$src" "$dst" "${draws[@]}"
}

redact_image_2() {
  local src=$1 dst=$2
  redact_light "$src" "$src.tmp" \
    -draw "rectangle 3980,12 4580,78" \
    -draw "rectangle 2680,170 4550,250" \
    -draw "rectangle 2850,250 4100,1150"

  redact_dark "$src.tmp" "$dst" \
    -draw "rectangle 60,205 1150,250" \
    -draw "rectangle 90,332 2100,372" \
    -draw "rectangle 90,612 1450,656" \
    -draw "rectangle 90,652 680,696"

  rm -f "$src.tmp"
}

redact_image_3() {
  local src=$1 dst=$2
  redact_light "$src" "$dst" \
    -draw "rectangle 70,118 2280,205" \
    -draw "rectangle 2360,118 4580,205" \
    -draw "rectangle 3980,12 4580,78" \
    -draw "rectangle 280,210 4580,280" \
    -draw "rectangle 300,280 1180,950" \
    -draw "rectangle 2550,280 3450,950"
}

main() {
  for id in 1 2 3; do
    local f="$IMG_DIR/${id}.png"
  local orig="$IMG_DIR/${id}.orig.png"
    [[ -f "$orig" ]] || backup_if_needed "$f"
    cp "$orig" "$f"
  done

  redact_image_1 "$IMG_DIR/1.png" "$IMG_DIR/1.png"
  redact_image_2 "$IMG_DIR/2.png" "$IMG_DIR/2.png"
  redact_image_3 "$IMG_DIR/3.png" "$IMG_DIR/3.png"

  echo "Done. Originals kept as *.orig.png"
}

main "$@"
