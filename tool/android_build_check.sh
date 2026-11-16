#!/usr/bin/env bash
# Builds a throwaway Flutter app that depends on this checkout and proves that the Android side
# of the plugin compiles inside a real app and ships the printerModel event.
# Usage, from the repo root: bash ./tool/android_build_check.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/zebrautil_android_check"

step() { printf '\n==> %s\n' "$*"; }

step "Creating throwaway app in $app"
mkdir -p "$app"
cp "$repo/.fvmrc" "$app/.fvmrc"
cd "$app"
fvm flutter create --platforms=android --project-name zebrautil_android_check --org co.evreka.check .

step "Adding $repo as path dependency 'zebrautil'"
fvm flutter pub add "zebrautil:{\"path\":\"$repo\"}"

# ponytail: the plugin needs minSdk 21, Flutter's default app minSdk is already above it.

step "Adding the README's META-INF packaging excludes to the app"
gradle=android/app/build.gradle.kts
test -f "$gradle"
cat >> "$gradle" <<'EOF'

android {
    packaging {
        resources.excludes += listOf(
            "META-INF/LICENSE.txt",
            "META-INF/NOTICE.txt",
            "META-INF/NOTICE",
            "META-INF/LICENSE",
            "META-INF/DEPENDENCIES",
        )
    }
}
EOF

step "Building debug APK"
fvm flutter build apk --debug
apk=build/app/outputs/flutter-apk/app-debug.apk
test -f "$apk"

step "Checking the APK's dex files carry the printerModel event"
mkdir -p "$tmp/dex"
unzip -q -o "$apk" 'classes*.dex' -d "$tmp/dex"
grep -qa printerModel "$tmp"/dex/classes*.dex || { echo "printerModel not found in classes*.dex" >&2; exit 1; }
grep -qa 'com/rubdev/zebrautil/Printer;' "$tmp"/dex/classes*.dex

step "OK: plugin's Android side builds inside an app and ships printerModel"
