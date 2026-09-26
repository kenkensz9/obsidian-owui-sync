FROM denoland/deno:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip git ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages oikb

# 公式(vrtmrz)のlivesync-bridge。チャンク分割/ドキュメント形式がObsidian本体と完全互換。
WORKDIR /opt
RUN git clone --recursive https://github.com/vrtmrz/livesync-bridge.git bridge
WORKDIR /opt/bridge
RUN deno install

# vault の実体は /vault に置く（Railway ダッシュボードの Volumes 機能でここにマウントする）
COPY entrypoint.sh /entrypoint.sh
COPY write_api.py /opt/write_api.py
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]