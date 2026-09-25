#!/usr/bin/env bash
# Local Linux pre-push checks (ARCHITECTURE.md §8.2). Run before every push:
#     scripts/preflight.sh
# Environment:
#     XCODEGEN   xcodegen binary to use (default: xcodegen on PATH), e.g. a Linux build of 2.46.0
#     SWIFT_BIN  optional directory prepended to PATH for swift/swiftc,
#                e.g. /opt/swift/swift-6.4.0-RELEASE-ubuntu24.04/usr/bin
# The run regenerates SayoneHealth.xcodeproj, the Info.plists and the entitlements;
# commit them if they changed.
set -euo pipefail

cd "$(dirname "$0")/.."
XCODEGEN="${XCODEGEN:-xcodegen}"
if [ -n "${SWIFT_BIN:-}" ]; then
  export PATH="$SWIFT_BIN:$PATH"
fi

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'preflight: FAILED: %s\n' "$*" >&2; exit 1; }

step "1/6 lint"
python3 scripts/lint.py

step "2/6 string catalog up to date"
python3 scripts/build_strings.py --check

step "3/6 swiftc -parse (Shared, iOS, Watch)"
find Shared iOS Watch -name '*.swift' -print0 | xargs -0 -r -n 40 swiftc -parse

step "4/6 swift test (SayoneCore)"
swift test --package-path Packages/SayoneCore

step "5/6 xcodegen generate ($("$XCODEGEN" --version 2>/dev/null || echo "$XCODEGEN"))"
USER=${USER:-ci} LOGNAME=${LOGNAME:-ci} "$XCODEGEN" generate --spec project.yml --quiet

step "6/6 generated project checks"
P=SayoneHealth.xcodeproj/project.pbxproj
# Verbatim from §8.2 (match phase *definitions* only; the naive pattern also hits PBXBuildFile lines).
test "$(grep -cE '^[[:space:]]*[0-9A-F]{24} /\* Embed Watch Content \*/ = \{' "$P")" = 1 || fail "expected exactly 1 'Embed Watch Content' phase"
test "$(grep -cE '^[[:space:]]*[0-9A-F]{24} /\* Embed Foundation Extensions \*/ = \{' "$P")" = 2 || fail "expected exactly 2 'Embed Foundation Extensions' phases"
grep -qF 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";' "$P" || fail "watch app is not embedded at \$(CONTENTS_FOLDER_PATH)/Watch"
test -f SayoneHealth.xcodeproj/xcshareddata/xcschemes/SayoneHealth.xcscheme || fail "missing shared scheme SayoneHealth"
test -f SayoneHealth.xcodeproj/xcshareddata/xcschemes/SayoneHealthWatch.xcscheme || fail "missing shared scheme SayoneHealthWatch"
grep -A4 'knownRegions = (' "$P" | grep -qE '^[[:space:]]+ru,$' || fail "knownRegions does not contain ru"
# Additional checks from §2.2's validation list.
grep -A2 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";' "$P" | grep -qF 'dstSubfolderSpec = 16;' || fail "Embed Watch Content must use dstSubfolderSpec = 16"
grep -qF 'IPHONEOS_DEPLOYMENT_TARGET = 18.0;' "$P" || fail "iOS deployment target is not 18.0"
grep -qF 'WATCHOS_DEPLOYMENT_TARGET = 11.0;' "$P" || fail "watchOS deployment target is not 11.0"
for f in iOS/App/Info.plist iOS/Widgets/Info.plist Watch/App/Info.plist Watch/Widgets/Info.plist \
         iOS/App/SayoneHealth.entitlements iOS/Widgets/SayoneHealthWidgets.entitlements \
         Watch/App/SayoneHealthWatch.entitlements Watch/Widgets/SayoneHealthWatchWidgets.entitlements; do
  test -f "$f" || fail "xcodegen did not write $f"
done
python3 - <<'EOF' || fail "INAlternativeAppNames not serialized correctly"
import plistlib
want = ["Sayone", "Сейон", "Сейон Хелс"]
for p in ("iOS/App/Info.plist", "Watch/App/Info.plist"):
    with open(p, "rb") as f:
        names = [d.get("INAlternativeAppName") for d in plistlib.load(f).get("INAlternativeAppNames", [])]
    assert names == want, (p, names)
EOF
# Lint again: the regenerated plists and entitlements are now on disk.
python3 scripts/lint.py --quiet >/dev/null || { python3 scripts/lint.py --quiet; fail "lint failed on the regenerated files"; }

if command -v git >/dev/null 2>&1 && ! git diff --quiet -- SayoneHealth.xcodeproj iOS Watch 2>/dev/null; then
  printf '\nnote: the regenerated project differs from the committed one; commit it:\n'
  git diff --stat -- SayoneHealth.xcodeproj iOS Watch || true
fi
printf '\npreflight: OK\n'
