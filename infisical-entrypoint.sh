#!/bin/sh
set -eu

: "${INFISICAL_CLIENT_ID:?INFISICAL_CLIENT_ID is required}"
: "${INFISICAL_CLIENT_SECRET:?INFISICAL_CLIENT_SECRET is required}"

TOKEN="$(infisical login \
  --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" \
  --silent \
  --plain)"

: "${TOKEN:?Infisical authentication failed}"

unset INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET

exec infisical run \
  --token="$TOKEN" \
  --projectId="d2d52a43-08b7-46fd-9176-1a72c9d6ba32" \
  --env="prod" \
  --path="/obsidian-owui-sync" \
  -- /entrypoint.sh "$@"