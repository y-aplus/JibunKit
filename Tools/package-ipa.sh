#!/usr/bin/env bash
# Check a built JibunKit app, ad-hoc sign it with its extensions and package it
# as an IPA. Run on macOS from the repository root, after `tuist generate` and
# an unsigned `xcodebuild build`:
#
#   Tools/package-ipa.sh path/to/JibunKit_App.app artifacts/JibunKit.ipa
#
# The checks are the ones every build needs: arm64 executables, extension IDs
# and versions that match the app, the generated InfoPlist translations and the
# App Group in the signed entitlements. The ad-hoc signature only makes the
# bundle well formed; SideStore or AltStore re-signs it with the user's account.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 APP OUTPUT_IPA" >&2
  exit 2
fi
app="${1%/}"
output="$2"
entitlements_root=Derived

fail() { echo "error: $*" >&2; exit 1; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

check_executable() {
  local bundle="$1" executable
  executable="$bundle/$(plist_value "$bundle/Info.plist" CFBundleExecutable)"
  [[ -x "$executable" ]] || fail "$bundle has no executable"
  file "$executable" | grep -q arm64 || fail "$executable is not arm64"
  echo "executable: $executable"
}

# Tuist writes TARGET.entitlements under Derived for a target that has any.
entitlements_for() {
  local found
  found="$(find "$entitlements_root" -type f -name "$1.entitlements")"
  [[ "$(printf '%s' "$found" | grep -c .)" -le 1 ]] || fail "more than one $1.entitlements: $found"
  printf '%s' "$found"
}

sign() {
  local bundle="$1" entitlements="$2"
  if [[ -n "$entitlements" ]]; then
    codesign --force --sign - --timestamp=none --generate-entitlement-der \
      --entitlements "$entitlements" "$bundle"
  else
    codesign --force --sign - --timestamp=none "$bundle"
  fi
}

[[ -d "$app" ]] || fail "missing app bundle $app"
check_executable "$app"
app_id="$(plist_value "$app/Info.plist" CFBundleIdentifier)"
version="$(plist_value "$app/Info.plist" CFBundleShortVersionString)"
build="$(plist_value "$app/Info.plist" CFBundleVersion)"
app_group="$(plist_value "$app/Info.plist" JibunKitAppGroup 2>/dev/null || true)"
echo "app: $app_id $version ($build)"
python3 Tools/verify-localized-info-plist.py GeneratedFeatureResources/App "$app"

shopt -s nullglob
for appex in "$app"/PlugIns/*.appex; do
  name="$(basename "$appex" .appex)"   # JibunKitWidget_Extension
  kind="${name#JibunKit}"
  kind="${kind%_Extension}"            # Widget
  check_executable "$appex"
  appex_id="$(plist_value "$appex/Info.plist" CFBundleIdentifier)"
  [[ "$appex_id" == "$app_id".* ]] || fail "$name bundle ID $appex_id is not under $app_id"
  [[ "$(plist_value "$appex/Info.plist" CFBundleShortVersionString)" == "$version" ]] || fail "$name version differs from the app"
  [[ "$(plist_value "$appex/Info.plist" CFBundleVersion)" == "$build" ]] || fail "$name build differs from the app"
  if [[ -d "GeneratedFeatureResources/$kind" ]]; then
    python3 Tools/verify-localized-info-plist.py "GeneratedFeatureResources/$kind" "$appex"
  fi
  case "$kind" in
    Share | Action)
      python3 Tools/verify-share-extension.py --app "$app" --entitlements-root "$entitlements_root" --kind "$kind" ;;
    *)
      sign "$appex" "$(entitlements_for "JibunKit$kind-Extension")" ;;
  esac
done

app_entitlements="$(entitlements_for JibunKit-App)"
[[ -n "$app_entitlements" ]] || fail "missing JibunKit-App.entitlements under $entitlements_root"
sign "$app" "$app_entitlements"
codesign --verify --deep --strict "$app"
if [[ -n "$app_group" ]]; then
  for bundle in "$app" "$app"/PlugIns/*.appex; do
    signed="$(codesign --display --entitlements :- "$bundle" 2>&1)"
    case "$(basename "$bundle")" in
      JibunKitWidget_Extension.appex | JibunKit_App.app)
        [[ "$signed" == *"$app_group"* ]] || fail "$(basename "$bundle") is not signed with $app_group" ;;
    esac
  done
fi

payload="$(mktemp -d)"
mkdir -p "$payload/Payload" "$(dirname "$output")"
ditto "$app" "$payload/Payload/JibunKit.app"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
rm -f "$output"
(cd "$payload" && ditto -c -k --sequesterRsrc --keepParent Payload "$output")
rm -rf "$payload"
unzip -tq "$output"
shasum --algorithm 256 "$output"
