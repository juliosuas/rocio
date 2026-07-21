#!/bin/sh
set -eu

key=${ROCIO_SUPABASE_PUBLISHABLE_KEY:-}
if [ -z "$key" ]; then
  exit 0
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
