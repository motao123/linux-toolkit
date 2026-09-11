#!/bin/bash
#
# change_mirror.sh
# Docker Hub 镜像加速一键配置
# 自动检测服务器是否位于中国大陆，写入对应的 registry-mirrors 配置
#
# 说明:
#   - 国内公共镜像源时效性强、失效频繁，本列表更新于 2026-09，
#     失效时可参考长期维护的汇总: https://github.com/dongyubin/DockerHub
#   - 已存在的 /etc/docker/daemon.json 会先备份为 daemon.json.bak.<时间戳>
#     再覆盖（原配置中的其他设置如 data-root 需自行合并回去）
#

set -u

DAEMON_JSON="/etc/docker/daemon.json"

if ! systemctl status docker >/dev/null 2>&1; then
    echo "[ERROR] Docker daemon is not available"
    exit 1
fi

echo "[NOTICE] Checking whether this host is in china mainland..."

geo_check() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 10 https://ipapi.co/country_code_iso3 2>/dev/null
    else
        wget -qO - -T 10 https://ipapi.co/country_code_iso3 2>/dev/null
    fi
}

# 国内公共镜像源（2026-09 实测可用，失效频繁请自行替换）
CN_MIRRORS='[
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.jiaxin.site"
]'

# 海外使用 Google 的 Docker Hub 缓存镜像（由 Artifact Registry 承载，仍可用）
GLOBAL_MIRRORS='[
    "https://mirror.gcr.io"
]'

if [ "$(geo_check)" = "CHN" ]; then
    echo "[INFO] Selected CN Docker mirror servers"
    MIRRORS="$CN_MIRRORS"
else
    echo "[INFO] Selected global Docker mirror server"
    MIRRORS="$GLOBAL_MIRRORS"
fi

if [ -f "$DAEMON_JSON" ]; then
    BACKUP="${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
    echo "[NOTICE] $DAEMON_JSON exists, backup to $BACKUP"
    cp -f "$DAEMON_JSON" "$BACKUP" || { echo "[ERROR] backup failed"; exit 1; }
fi

echo "[INFO] writing $DAEMON_JSON"
mkdir -p /etc/docker
cat > "$DAEMON_JSON" << EOF
{
  "registry-mirrors": ${MIRRORS}
}
EOF

echo "[INFO] restarting docker daemon"
systemctl restart docker
echo "[INFO] OK"
