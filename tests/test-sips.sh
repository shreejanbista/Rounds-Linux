#!/usr/bin/env bash
# Tests the sips stand-in the way Rounds calls it. Needs libvips and ImageMagick (to make test images).
# Usage: tests/test-sips.sh [path-to-sips]   (defaults to ./bin/sips)
set -uo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SIPS="${1:-$here/bin/sips}"
command -v magick >/dev/null || { echo "ImageMagick (magick) is needed to make test images"; exit 2; }

t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/out dir"
pass=0 fail=0
check() { if eval "$2"; then echo "  ok    $1"; ((pass++)); else echo "  FAIL  $1"; ((fail++)); fi; }
size() { echo "$(vipsheader -f width "$1" 2>/dev/null)x$(vipsheader -f height "$1" 2>/dev/null)"; }
resize() { "$SIPS" -Z "$1" -s format jpeg -s formatOptions 84 "$2" --out "$3" 2>/dev/null; }

magick -size 1170x2532 gradient:skyblue-navy "$t/tall.png"
magick -size 2880x1800 plasma:fractal "$t/wide.jpg"
magick -size 300x200 xc:orange "$t/small.png"
magick -size 800x800 xc:none -fill red -draw "circle 400,400 400,100" "$t/clear bg.png"
echo "not an image" > "$t/fake.png"

echo "sips stand-in: $SIPS"
resize 600 "$t/tall.png" "$t/out dir/tall.jpg"
check "tall screenshot fits longest side (277x600)" '[[ "$(size "$t/out dir/tall.jpg")" == 277x600 ]]'
resize 600 "$t/wide.jpg" "$t/out dir/wide.jpg"
check "wide screenshot fits longest side (600x375)" '[[ "$(size "$t/out dir/wide.jpg")" == 600x375 ]]'
check "output is a JPEG" '[[ "$(file -b --mime-type "$t/out dir/wide.jpg")" == image/jpeg ]]'
resize 600 "$t/small.png" "$t/out dir/small.jpg"
check "small image is not enlarged (300x200)" '[[ "$(size "$t/out dir/small.jpg")" == 300x200 ]]'
resize 600 "$t/clear bg.png" "$t/out dir/clear.jpg"
check "transparency becomes white" '[[ "$(magick "$t/out dir/clear.jpg" -format "%[pixel:p{5,5}]" info:)" == "srgb(255,255,255)" ]]'
out="$("$SIPS" -g pixelWidth -g pixelHeight "$t/tall.png" 2>/dev/null)"
check "reports size the way Rounds parses it" '[[ "$out" == *"pixelWidth: 1170"* && "$out" == *"pixelHeight: 2532"* ]]'
check "missing file fails" '! resize 600 "$t/nope.png" "$t/out dir/nope.jpg"'
check "broken image fails" '! resize 600 "$t/fake.png" "$t/out dir/fake.jpg"'
check "unsupported option fails" '! "$SIPS" --rotate 90 "$t/tall.png" 2>/dev/null'
check "no half-written files left" '[[ -z "$(ls -A "$t/out dir" | grep "^\.sips")" ]]'

echo "$pass passed, $fail failed"
((fail == 0))
