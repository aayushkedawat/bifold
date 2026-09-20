#!/usr/bin/env bash
#
# verify-sdk.sh — read-only verification of the iOS 27.1 SDK and iPhone Duo simulator.
#
# Ground rule 1 in CLAUDE.md: never invent Apple APIs. Apple's documentation site is
# JavaScript-rendered and does not yield declarations to plain fetching, so the SDK headers
# are the only practical source of truth. This script finds them and prints the declarations
# for every symbol bifold is considering, so they can be pasted into API_NOTES.md.
#
# Reads only. Installs nothing, changes nothing, opens no simulator.
#
# Usage:  bash scripts/verify-sdk.sh
# Exit:   0 if the 27.1 SDK was found and searched, 1 if it is not installed yet.

set -uo pipefail

# Symbols recorded as candidates in API_NOTES.md. Keep the two lists in sync.
SYMBOLS=(
  UIViewReservedRegion
  reservedRegionsOfKind
  reservedRegions
  UIHingeInteraction
  UIHingeStatus
  UIHingeContext
  UIArrangementViewController
)

hr() { printf '%*s\n' 78 '' | tr ' ' '-'; }
section() { echo; hr; echo "$1"; hr; }

section "Toolchain"
echo "xcode-select -p : $(xcode-select -p 2>/dev/null || echo '(none)')"
xcodebuild -version 2>/dev/null || echo "xcodebuild: unavailable"
echo "date          : $(date +%Y-%m-%d)"

section "Simulator runtimes"
xcrun simctl list runtimes 2>/dev/null | grep -i ios || echo "(none found)"

section "iPhone Duo simulator device type"
# Ground rule 4: all testing happens in the Duo simulator. Confirm it exists before
# claiming anything was verified there.
if duo=$(xcrun simctl list devicetypes 2>/dev/null | grep -iE 'duo|fold'); then
  echo "$duo"
else
  echo "NOT FOUND — no device type matching 'duo' or 'fold'."
  echo "Anything claimed as simulator-verified is currently unverifiable."
fi

section "Locating the iOS SDK"
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true)
echo "SDK path    : ${SDK_PATH:-(not found)}"
echo "SDK version : ${SDK_VERSION:-(not found)}"

if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
  echo
  echo "RESULT: no iOS SDK found. Install Xcode 27.1, then re-run."
  exit 1
fi

case "$SDK_VERSION" in
  27.1*|27.[2-9]*|2[89].*|3[0-9].*)
    echo "iOS 27.1+ SDK present — symbol search will be meaningful."
    ;;
  *)
    echo
    echo "RESULT: iOS 27.1 SDK not found (have ${SDK_VERSION})."
    echo "The iPhone Duo symbols do not exist in this SDK. Nothing to verify yet."
    echo "Install Xcode 27.1 and re-run; until then every row in API_NOTES.md stays UNVERIFIED."
    exit 1
    ;;
esac

section "Availability constant (confirms 270100 spells iOS 27.1)"
# PR #193025 gates on __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100. Confirm the constant
# rather than trusting the MMmmpp convention.
AVAIL="$SDK_PATH/usr/include/AvailabilityVersions.h"
if [ -f "$AVAIL" ]; then
  grep -nE '__IPHONE_27_[0-9]+' "$AVAIL" || echo "(no __IPHONE_27_x constants found)"
else
  echo "AvailabilityVersions.h not at expected path: $AVAIL"
fi

UIKIT_HEADERS="$SDK_PATH/System/Library/Frameworks/UIKit.framework/Headers"
section "UIKit headers"
if [ ! -d "$UIKIT_HEADERS" ]; then
  echo "UIKit headers not found at: $UIKIT_HEADERS"
  echo "Falling back to a search across the whole SDK."
  UIKIT_HEADERS="$SDK_PATH"
else
  echo "$UIKIT_HEADERS"
fi

for sym in "${SYMBOLS[@]}"; do
  section "Symbol: $sym"
  # -w so 'reservedRegions' does not swallow every 'reservedRegionsOfKind' hit as noise;
  # -A4 to catch the API_AVAILABLE annotation, which usually trails the declaration.
  if ! grep -rnw -A4 "$sym" "$UIKIT_HEADERS" 2>/dev/null | head -60; then
    echo "NOT FOUND in UIKit headers."
  fi
done

section "Swift interface (declarations as Swift sees them)"
# The .swiftinterface carries the Swift spelling and @available annotations, which is what
# the Swift plugin code actually writes. Often clearer than the ObjC header.
SWIFTINTERFACE=$(find "$SDK_PATH/System/Library/Frameworks/UIKit.framework" \
  -name '*.swiftinterface' 2>/dev/null | head -5)
if [ -n "$SWIFTINTERFACE" ]; then
  for f in $SWIFTINTERFACE; do
    echo "--- $f"
    grep -nE 'reservedRegions|ReservedRegion|Hinge|ArrangementView' "$f" 2>/dev/null | head -40 \
      || echo "(no matches)"
  done
else
  echo "(no .swiftinterface found under UIKit.framework)"
fi

section "Next steps"
cat <<'EOF'
1. Paste each declaration above into API_NOTES.md and promote its status marker:
     UNVERIFIED / CORROBORATED / APPLE-NAMED  ->  VERIFIED
   with today's date and the header path as the source.
2. Answer the three open questions in API_NOTES.md under reservedRegionsOfKind:options: --
   coordinate space, whether .includeInactive exists, and the kind parameter's type.
3. Confirm UIHingeStatus really has exactly three cases. If so, correct FoldPose in
   CLAUDE.md, which currently drafts five.
4. Boot the Duo simulator and fill in the behavior log at the end of API_NOTES.md:
   region arrival timing, hinge-to-region lag, and whether a folded outer display
   reports no regions.
EOF
