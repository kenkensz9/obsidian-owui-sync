FROM node:20-slim

# oikb (Python) と livesync-headless (Node) を同居させる
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip git ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages oikb

# headless LiveSync クライアント
WORKDIR /opt
RUN git clone --depth 1 https://github.com/tgmstudios/obsidian-livesync-headless.git livesync
WORKDIR /opt/livesync
RUN npm install --omit=dev

# vault の実体は /vault に置く（Railway ダッシュボードの Volumes 機能でここにマウントする）
COPY entrypoint.sh /entrypoint.sh
COPY write_api.py /opt/write_api.py
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]