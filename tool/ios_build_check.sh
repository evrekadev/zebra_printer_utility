#!/usr/bin/env bash
# Builds a throwaway Flutter app that depends on this checkout and proves that the iOS side
# of the plugin registers and builds for a device (release) and for the simulator (debug).
# Usage, from the repo root: bash ./tool/ios_build_check.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/zebrautil_ios_check"

step() { printf '\n==> %s\n' "$*"; }

step "Creating throwaway app in $app"
mkdir -p "$app"
cp "$repo/.fvmrc" "$app/.fvmrc"
cd "$app"
fvm flutter create --platforms=ios --project-name zebrautil_ios_check --org co.evreka.check .

step "Adding $repo as path dependency 'zebrautil'"
fvm flutter pub add "zebrautil:{\"path\":\"$repo\"}"

step "Generating the iOS Podfile"
if [ ! -f ios/Podfile ]; then
  fvm flutter build ios --config-only --no-codesign
fi
grep -q 'use_frameworks!' ios/Podfile || { echo "Podfile has no use_frameworks!" >&2; exit 1; }

step "Setting iOS deployment target to 15.0"
if grep -qE "^#? *platform :ios" ios/Podfile; then
  sed -i '' -E "s/^#? *platform :ios.*/platform :ios, '15.0'/" ios/Podfile
else
  printf "platform :ios, '15.0'\n%s\n" "$(cat ios/Podfile)" > ios/Podfile
fi
sed -i '' -E 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/' ios/Runner.xcodeproj/project.pbxproj
grep -q "^platform :ios, '15.0'" ios/Podfile
if grep -qE 'IPHONEOS_DEPLOYMENT_TARGET = (1[0-4]|[0-9])\.' ios/Runner.xcodeproj/project.pbxproj; then
  echo "Xcode project still has a deployment target below 15.0" >&2; exit 1
fi

step "Building for iOS device (release, no codesign)"
fvm flutter build ios --no-codesign

step "Checking the device build linked libZSDK_API.a"
test -f ios/.symlinks/plugins/zebrautil/ios/libZSDK_API.a
grep -qa MfiBtPrinterConnection build/ios/iphoneos/Runner.app/Runner
grep -qa 'GET:withPrinterConnection' build/ios/iphoneos/Runner.app/Runner

step "Checking the generated registrant registers ZebraUtilPlugin"
registrant=ios/Runner/GeneratedPluginRegistrant.m
grep -q '#import <zebrautil/ZebraUtilPlugin.h>' "$registrant"
grep -q '\[ZebraUtilPlugin registerWithRegistrar:' "$registrant"

step "Building for iOS simulator (debug)"
fvm flutter build ios --simulator --debug

step "OK: plugin registers and builds for iOS device and simulator"
