#!/bin/sh
# Local test build: ad-hoc signed, sandboxed, WITHOUT the push entitlement (aps-environment needs a provisioning profile,
# without it macOS refuses to launch the app). Output: build/Build/Products/Debug/Church TV OS.app
cd "$(dirname "$0")"
xcodebuild -project ChurchTVMac.xcodeproj -scheme ChurchTVMac -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGN_ENTITLEMENTS="$PWD/Resources/ChurchTVMac-LocalTest.entitlements" \
  DEVELOPMENT_TEAM= "$@" build
