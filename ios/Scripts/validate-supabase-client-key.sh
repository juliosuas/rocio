#!/bin/sh
set -eu

key=${ROCIO_SUPABASE_PUBLISHABLE_KEY:-}
if [ -z "$key" ]; then
  # Debug builds intentionally support the local demo/unconfigured UI. CI also
  # creates an unsigned Release archive so it can verify the project without
  # storing a production credential. A signed Release, however, must never
  # produce a TestFlight/App Store binary that cannot reach Supabase.
  if [ "${CONFIGURATION:-}" = "Debug" ] || [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
    exit 0
  fi

  echo "error: ROCIO_SUPABASE_PUBLISHABLE_KEY is required for a signed Release build." >&2
  exit 1
fi

case "$key" in
  sb_publishable_*)
    suffix=${key#sb_publishable_}
    if [ "${#suffix}" -lt 20 ]; then
      echo "error: ROCIO_SUPABASE_PUBLISHABLE_KEY is still a placeholder or is incomplete." >&2
      exit 1
    fi
    ;;
  *)
    echo "error: iOS accepts only a Supabase sb_publishable_ key; never embed a secret or service-role key." >&2
    exit 1
    ;;
esac
