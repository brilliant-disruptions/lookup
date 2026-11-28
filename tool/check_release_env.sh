#!/bin/sh
# Refuses a release build that doesn't know the relay (relay/README.md).
# Clouds, rare events, invites and "Seen near you" all come through it, and
# without clouds the alert gate can't check the sky: unknown cloud lets an
# alert through. Run before every `flutter build … --release`.
#
#   LOOKUP_RELAY_URL=https://… tool/check_release_env.sh
set -eu

url="${LOOKUP_RELAY_URL:-}"
if [ -z "$url" ]; then
  echo "error: LOOKUP_RELAY_URL is empty. A release build needs the relay: no relay, no clouds." >&2
  echo "       Build with --dart-define=LOOKUP_RELAY_URL=https://… (see relay/README.md)." >&2
  exit 1
fi
case "$url" in
  https://*) ;;
  *)
    echo "error: LOOKUP_RELAY_URL must be an https:// address, got: $url" >&2
    exit 1
    ;;
esac
case "$url" in
  *localhost*|*127.0.0.1*|*.test|*.test/*)
    echo "error: LOOKUP_RELAY_URL points at a local or test host: $url" >&2
    exit 1
    ;;
esac
echo "LOOKUP_RELAY_URL ok: $url"
