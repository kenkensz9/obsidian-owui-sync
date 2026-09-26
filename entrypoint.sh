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

E2EE_PASSPHRASE="${E2EE_PASSPHRASE:-}"
OBFUSCATE_PASSPHRASE="${OBFUSCATE_PASSPHRASE-}"

# チャンク分割の設定。動作確認済みの値。
CHUNK_CUSTOM_SIZE="${CHUNK_CUSTOM_SIZE:-100}"
CHUNK_MINIMUM_SIZE="${CHUNK_MINIMUM_SIZE:-20}"

# useRemoteTweaks: リモート側の設定(Property Encryption等)を
# bridgeが勝手に上書きしてしまう問題があったため、デフォルトはfalse。
# trueにする場合は、Obsidian側の設定と完全に合わせてから使うこと。
USE_REMOTE_TWEAKS="${USE_REMOTE_TWEAKS:-false}"

mkdir -p "$VAULT_PATH"
mkdir -p /opt/bridge/dat

# --- 1. livesync-bridge の設定ファイルを環境変数から生成 -----------------
# 参考: https://github.com/vrtmrz/livesync-bridge の dat/config.sample.json
cat > /opt/bridge/dat/config.json <<JSON
{
  "peers": [
    {
      "type": "couchdb",
      "name": "obsidian-remote",
      "group": "main",
      "database": "${COUCHDB_DATABASE}",
      "username": "${COUCHDB_USER}",
      "password": "${COUCHDB_PASSWORD}",
      "url": "${COUCHDB_URI}",
      "passphrase": "${E2EE_PASSPHRASE}",
      "obfuscatePassphrase": "${OBFUSCATE_PASSPHRASE}",
      "baseDir": "",
      "customChunkSize": ${CHUNK_CUSTOM_SIZE},
      "minimumChunkSize": ${CHUNK_MINIMUM_SIZE},
      "useRemoteTweaks": ${USE_REMOTE_TWEAKS}
    },
    {
      "type": "storage",
      "name": "local-vault",
      "group": "main",
      "baseDir": "${VAULT_PATH}"
    }
  ]
}
JSON
chmod 600 /opt/bridge/dat/config.json

echo "[worker] generated config:"
cat /opt/bridge/dat/config.json | sed -E 's/"(password|passphrase|obfuscatePassphrase)": "[^"]*"/"\1": "***"/g'

# --- 2. livesync-bridge をバックグラウンドで常駐(異常終了しても自動再起動) ---
echo "[worker] starting livesync-bridge (deno)"
cd /opt/bridge
(
  while true; do
    deno task run
    echo "[bridge] process exited, restarting in ${SYNC_INTERVAL}s..."
    sleep "${SYNC_INTERVAL}"
  done
) &
BRIDGE_PID=$!

# --- 3. 書き込み用APIをバックグラウンドで起動 ----------------------------
echo "[worker] starting write_api on :${WRITE_API_PORT:-8090}"
python3 /opt/write_api.py &
WRITE_API_PID=$!

# CouchDB からの初回フル取得を待つ
sleep "${INITIAL_WAIT:-90}"

# --- 4. oikb の watch モードで Knowledge Base へ差分同期 ------------------
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
wait -n "$BRIDGE_PID" "$OIKB_PID" "$WRITE_API_PID"
echo "[worker] a child process exited; shutting down"
exit 1