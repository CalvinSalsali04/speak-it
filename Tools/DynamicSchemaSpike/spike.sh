#!/bin/bash
# A narrow capability check: does FoundationModels let us bound a span schema at
# runtime from THIS capture's atom count, and bound the segment count too?
#
# Five small programs, each compiled on its own. That is the whole design: a
# wrong guess about one API shape costs one answer instead of all of them, and
# the report says which shapes compiled rather than "the build failed". Nothing
# here touches the app, the corpus, or any sealed set.
#
#   ./Tools/DynamicSchemaSpike/spike.sh
#
# A1  runtime .range guide on Int            -- the preferred span bound
# A2  anyOf enumeration of this capture's ids -- the fallback if A1 is absent
# B   runtime min/max on an array            -- the segment-count bound
# C   generate under those bounds, print raw -- bounds honoured, not just accepted
# D   decode, validate and slice the original transcript
#
# A1/A2/B need no model. C and D need an Apple Intelligence device and print
# SKIPPED elsewhere.
set -uo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
OUT="${SPIKE_OUT:-$SP/build}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$OUT"

VARIANTS=(a1-int-range a2-anyof-ids b-array-bounds c-generate-raw d-decode-and-slice)
declare -a BUILT=()

echo "== compiling =="
for variant in "${VARIANTS[@]}"; do
  work="$OUT/$variant"
  mkdir -p "$work"
  # swiftc wants top-level code in a file called main.swift, so each variant is
  # copied under that name next to its own copy of the atom helpers.
  cp "$SP/atoms.swift" "$work/atoms.swift"
  cp "$SP/variant-$variant.swift" "$work/main.swift"
  if xcrun swiftc -O -o "$work/run" "$work/atoms.swift" "$work/main.swift" 2> "$work/build-errors.log"; then
    echo "  $variant COMPILED"
    BUILT+=("$variant")
  else
    echo "  $variant DID NOT COMPILE -- $work/build-errors.log"
    sed -n '1,12p' "$work/build-errors.log" | sed 's/^/      /'
  fi
done

echo
echo "== running =="
for variant in "${BUILT[@]}"; do
  echo "-- $variant"
  "$OUT/$variant/run" 2>&1 | sed 's/^/   /'
done

echo
echo "== summary =="
for variant in "${VARIANTS[@]}"; do
  if [[ " ${BUILT[*]} " == *" $variant "* ]]; then echo "  $variant compiled"; else echo "  $variant FAILED TO COMPILE"; fi
done
