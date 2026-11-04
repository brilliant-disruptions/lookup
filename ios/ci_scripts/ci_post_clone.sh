#!/bin/sh
# Xcode Cloud runs this after cloning, before resolving packages and building.
# It installs Flutter, generates Flutter's iOS build config and installs pods.
# Docs: https://docs.flutter.dev/deployment/cd#xcode-cloud
set -e

# Pin to the stable channel; switch to a tag (e.g. -b 3.47.7) for fully
# reproducible builds.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter --version
flutter precache --ios
flutter pub get

# Generated.xcconfig with a unique, increasing build number per Xcode Cloud run
# (TestFlight rejects duplicate build numbers). Marketing version comes from
# pubspec.yaml.
# The relay (relay/README.md): Seen near you and invite links. Not a secret;
# set LOOKUP_RELAY_URL in the Xcode Cloud workflow to point somewhere else.
RELAY_URL="${LOOKUP_RELAY_URL:-https://lookup-relay.brilliant-disruptions.workers.dev}"
flutter build ios --config-only --release --no-codesign --build-number="${CI_BUILD_NUMBER:-1}" \
  --dart-define=LOOKUP_RELAY_URL="$RELAY_URL"

HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
cd ios && pod install

exit 0
