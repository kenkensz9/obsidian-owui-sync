#!/bin/bash
set -euo pipefail

VAULT_PATH="${VAULT_PATH:-/vault}"
SYNC_INTERVAL="${SYNC_INTERVAL_SECONDS:-30}"
OIKB_DEBOUNCE="${OIKB_DEBOUNCE:-60}"

: "${COUCHDB_URI:?COUCHDB_URI is required}"
: "${COUCHDB_DATABASE:?COUCHDB_DATABASE is required}"
: "${COUCHDB_USER:?COUCHDB_USER is required}"
: "${COUCHDB_PASSWORD:?COUCHDB_PASSWORD is required}"
: "${OPEN_WEBUI_URL:?OPEN_WEBUI_URL is required}"
: "${OPEN_WEBUI_API_KEY:?OPEN_WEBUI_API_KEY is required}"
: "${OIKB_KB_ID:?OIKB_KB_ID is required}"
: "${WRITE_API_SECRET:?WRITE_API_SECRET is required}"

mkdir -p "$VAULT_PATH"

# --- 1. LiveSync クライアントの設定を環境変数から生成 -------------------
E2EE_ENABLED="${E2EE_ENABLED:-false}"
E2EE_PASSPHRASE="${E2EE_PASSPHRASE:-}"

cat > /opt/livesync/config.json <<EOF
{
  "vaultPath": "${VAULT_PATH}",
  "couchDB": {
    "uri": "${COUCHDB_URI}",
    "database": "${COUCHDB_DATABASE}",
    "username": "${COUCHDB_USER}",
    "password": "${COUCHDB_PASSWORD}"
  },
  "e2ee": {
    "enabled": ${E2EE_ENABLED},
    "passphrase": "${E2EE_PASSPHRASE}"
  },
  "syncIntervalSeconds": ${SYNC_INTERVAL}
}
EOF
chmod 600 /opt/livesync/config.json

# --- 2. LiveSync をバックグラウンドで常駐 ------------------------------
echo "[worker] starting livesync-headless loop (vault=${VAULT_PATH}, interval=${SYNC_INTERVAL}s)"
cd /opt/livesync
(
  while true; do
    npm start
    echo "[livesync] process exited (likely one-shot sync finished), restarting in ${SYNC_INTERVAL}s..."
    sleep "${SYNC_INTERVAL}"
  done
) &
LIVESYNC_PID=$!

# --- 2b. 書き込み用APIをバックグラウンドで起動 --------------------------
echo "[worker] starting write_api on :${WRITE_API_PORT:-8090}"
python3 /opt/write_api.py &
WRITE_API_PID=$!

# CouchDB からの初回フル取得を待つ
sleep "${INITIAL_WAIT:-90}"

# --- 3. oikb の watch モードで Knowledge Base へ差分同期 ----------------
export OPEN_WEBUI_URL OPEN_WEBUI_API_KEY
echo "[worker] initial sync to KB ${OIKB_KB_ID}"
oikb sync "$VAULT_PATH" --kb-id "$OIKB_KB_ID" || echo "[worker] initial sync failed, continuing"

echo "[worker] starting oikb watch loop (debounce=${OIKB_DEBOUNCE}s)"
(
  while true; do
    oikb watch "$VAULT_PATH" --kb-id "$OIKB_KB_ID" --debounce "$OIKB_DEBOUNCE"
    echo "[oikb] watch process exited, restarting in 5s..."
    sleep 5
  done
) &
OIKB_PID=$!

# どれかが死んだらコンテナごと落として Railway に再起動させる
wait -n "$LIVESYNC_PID" "$OIKB_PID" "$WRITE_API_PID"
echo "[worker] a child process exited; shutting down"
exit 1