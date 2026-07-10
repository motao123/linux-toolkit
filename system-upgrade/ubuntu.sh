#!/bin/bash
#
# Ubuntu LTS 一键升级脚本
# 将当前 Ubuntu LTS 升级到下一个 LTS（如 22.04 -> 24.04）
#
# 用法:
#   chmod +x ubuntu.sh
#   ./ubuntu.sh                  # 交互模式，会要求确认
#   ./ubuntu.sh --yes            # 跳过确认
#   ./ubuntu.sh --verify         # 仅验证升级结果（重启后用）
#   ./ubuntu.sh --help
#
# 特性:
#   - 自动检查环境（root、磁盘空间、apt/dpkg 冲突）
#   - 无 swap 时自动创建 2G swap
#   - 开放 1022 端口（do-release-upgrade 备用 SSH）
#   - 用 systemd-run 启动升级，脱离 SSH 会话，防断连
#   - 实时监控升级日志
#   - 升级完成后自动重启
#
# 注意:
#   1. 升级过程中 SSH 会断连 3-5 分钟（sshd 被替换），属正常现象
#   2. 整个过程 30-60 分钟
#   3. 强烈建议先在云控制台打系统快照，本脚本不负责回滚
#   4. 第三方源（PPA、自编译软件）可能不兼容新版本，升级前请自行评估
#
set -euo pipefail

# ============ 颜色与日志 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] [WARN]${NC} $*"; }
err()  { echo -e "${RED}[$(date +'%H:%M:%S')] [ERROR]${NC} $*" >&2; }

# ============ 参数解析 ============
ASSUME_YES=false
VERIFY_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=true ;;
        --verify) VERIFY_ONLY=true ;;
        --help|-h)
            sed -n '2,25p' "$0"
            exit 0
            ;;
        *) err "未知参数: $arg"; exit 1 ;;
    esac
done

# ============ 基础检查 ============
[[ $EUID -ne 0 ]] && { err "必须 root 运行"; exit 1; }

if ! command -v lsb_release &>/dev/null; then
    err "lsb_release 命令不存在，请先装: apt install -y lsb-release"
    exit 1
fi

CUR_RELEASE=$(lsb_release -rs)
CUR_CODENAME=$(lsb_release -cs)

# LTS 版本映射
case "$CUR_RELEASE" in
    20.04) NEXT_RELEASE="22.04"; NEXT_CODENAME="jammy" ;;
    22.04) NEXT_RELEASE="24.04"; NEXT_CODENAME="noble" ;;
    24.04) NEXT_RELEASE="26.04"; NEXT_CODENAME="(未发布)" ;;
    *) err "当前版本 $CUR_RELEASE 不在支持升级的 LTS 列表"; exit 1 ;;
esac

# ============ --verify 模式 ============
if $VERIFY_ONLY; then
    log "=== 升级结果验证 ==="
    echo "当前版本: $(lsb_release -ds)"
    echo "运行内核: $(uname -r)"
    echo "uptime:   $(uptime -p)"
    echo ""
    echo "--- dpkg 完整性 ---"
    if dpkg --audit 2>&1 | grep -q .; then
        warn "有损坏的包:"
        dpkg --audit 2>&1
    else
        log "无损坏包 ✓"
    fi
    echo ""
    echo "--- apt 状态 ---"
    if apt-get check 2>&1; then
        log "apt 正常 ✓"
    else
        warn "apt 有问题"
    fi
    echo ""
    echo "--- 已装内核 ---"
    dpkg -l 'linux-image*' 2>/dev/null | grep '^ii' || true
    exit 0
fi

# ============ 升级前确认 ============
echo ""
echo "================================================"
echo "  Ubuntu LTS 一键升级"
echo "================================================"
echo "  当前:  Ubuntu $CUR_RELEASE LTS ($CUR_CODENAME)"
echo "  目标:  Ubuntu $NEXT_RELEASE LTS ($NEXT_CODENAME)"
echo "  内核:  $(uname -r)"
echo "  磁盘:  $(df -h / | awk 'NR==2 {print $4 " 可用"}')"
echo "  内存:  $(free -h | awk '/^Mem:/ {print $2 " 总计"}')"
echo "  Swap:  $(free -h | awk '/^Swap:/ {print $2}')"
echo "================================================"
echo ""
warn "升级前请确认:"
echo "  1. 已在云控制台打系统快照（本脚本不负责回滚）"
echo "  2. 已备份重要数据"
echo "  3. 第三方源、自编译软件已评估兼容性"
echo "  4. 升级过程中 SSH 会断连 3-5 分钟，正常现象"
echo "  5. 整个过程 30-60 分钟"
echo ""

if ! $ASSUME_YES; then
    read -p "确认开始升级? 输入 yes 继续: " confirm
    [[ "$confirm" == "yes" ]] || { err "已取消"; exit 1; }
fi

# ============ 步骤 1: 环境检查 ============
log "=== 步骤 1/6: 环境检查 ==="

# 磁盘空间检查（至少 5G）
AVAIL_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
if [[ "$AVAIL_GB" -lt 5 ]]; then
    err "磁盘可用空间不足 5G（当前 ${AVAIL_GB}G），中止"
    exit 1
fi
log "磁盘空间充足: ${AVAIL_GB}G 可用"

# 检查是否有正在运行的 apt/dpkg
if pgrep -x apt dpkg 2>/dev/null | grep -q .; then
    err "检测到 apt/dpkg 正在运行，请等待完成后重试"
    exit 1
fi
log "无 apt/dpkg 冲突"

# 检查被 hold 的包
HOLD_PKGS=$(apt-mark showhold 2>/dev/null || true)
if [[ -n "$HOLD_PKGS" ]]; then
    warn "以下包被 hold，可能影响升级: $HOLD_PKGS"
fi

# ============ 步骤 2: 创建 swap ============
log "=== 步骤 2/6: 检查 swap ==="
if [[ -n "$(swapon --show --noheadings 2>/dev/null)" ]]; then
    log "已有 swap，跳过"
    swapon --show
else
    warn "无 swap，创建 2G swap 文件"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "swap 创建完成"
    swapon --show
fi

# ============ 步骤 3: 防火墙开 1022 端口 ============
log "=== 步骤 3/6: 防火墙配置 ==="
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 1022/tcp 2>&1 | head -1
    log "已开放 1022/tcp（do-release-upgrade 备用 SSH）"
else
    info "ufw 未启用或不存在，跳过（请确保云安全组放行 1022 端口）"
fi

# ============ 步骤 4: 安装升级工具 + 系统全量升级 ============
log "=== 步骤 4/6: 安装升级工具并全量升级当前系统 ==="
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq 2>&1 | tail -3
apt-get install -y -qq update-manager-core 2>&1 | tail -3

log "执行 apt full-upgrade（保留现有配置文件）..."
apt-get -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" full-upgrade 2>&1 | tail -10
apt-get -y autoremove --purge 2>&1 | tail -3
apt-get clean

REMAINING=$(apt list --upgradable 2>/dev/null | grep -c -v '^Listing')
if [[ "$REMAINING" -gt 0 ]]; then
    warn "仍有 $REMAINING 个包未升级，可能影响 release upgrade"
else
    log "当前系统所有包已最新 ✓"
fi

# 确认 Prompt=lts
if ! grep -q "^Prompt=lts" /etc/update-manager/release-upgrades 2>/dev/null; then
    warn "release-upgrades 配置不是 Prompt=lts，自动修正"
    sed -i 's/^Prompt=.*/Prompt=lts/' /etc/update-manager/release-upgrades
fi

# 确认有新版本可用
log "检查是否有新版本可用..."
if ! do-release-upgrade -c 2>&1 | grep -q "New release"; then
    err "没有检测到可升级的新版本"
    exit 1
fi

# ============ 步骤 5: 启动 do-release-upgrade ============
log "=== 步骤 5/6: 启动 do-release-upgrade ==="

# 准备升级脚本
UPGRADE_SCRIPT="/root/run-release-upgrade.sh"
cat > "$UPGRADE_SCRIPT" << 'EOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C LANG=C
exec do-release-upgrade -f DistUpgradeViewNonInteractive --mode=server
EOF
chmod +x "$UPGRADE_SCRIPT"

# 清理可能残留的旧服务
systemctl stop ubuntu-release-upgrade 2>/dev/null || true
systemctl reset-failed ubuntu-release-upgrade 2>/dev/null || true

LOG_FILE="/var/log/dist-upgrade/main.log"

# 用 systemd-run 启动（关键：这是唯一能脱离 SSH 会话存活的方式）
info "用 systemd-run 启动升级服务（脱离 SSH 会话）..."
systemd-run \
    --unit=ubuntu-release-upgrade \
    --description="Ubuntu $CUR_RELEASE to $NEXT_RELEASE upgrade" \
    -- "$UPGRADE_SCRIPT"

log "升级服务已启动: ubuntu-release-upgrade.service"
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo ""
echo "================================================"
echo "  升级进行中，预计 30-60 分钟"
echo "  监控日志: tail -f $LOG_FILE"
echo "  查看服务: systemctl status ubuntu-release-upgrade"
echo ""
echo "  SSH 断连后可用以下方式重连:"
echo "    ssh -p 1022 root@${SERVER_IP}"
echo "    （原 22 端口会在升级中断 3-5 分钟）"
echo "================================================"

# ============ 步骤 6: 监控升级进度 ============
log "=== 步骤 6/6: 监控升级进度 ==="
echo ""

LAST_LINE=""
STUCK_COUNTER=0
START_TIME=$(date +%s)

while true; do
    # 检查服务是否还在运行
    SERVICE_STATUS=$(systemctl is-active ubuntu-release-upgrade 2>/dev/null || echo "unknown")

    if [[ "$SERVICE_STATUS" != "active" ]]; then
        END_TIME=$(date +%s)
        ELAPSED=$(( (END_TIME - START_TIME) / 60 ))
        echo ""
        log "升级服务已结束（状态: $SERVICE_STATUS，耗时约 ${ELAPSED} 分钟）"
        break
    fi

    # 读取日志最后一行（非 DEBUG 行）
    CURRENT_LINE=$(tail -100 "$LOG_FILE" 2>/dev/null | grep -v DEBUG | tail -1 || true)
    if [[ -n "$CURRENT_LINE" && "$CURRENT_LINE" != "$LAST_LINE" ]]; then
        TS=$(echo "$CURRENT_LINE" | awk '{print $1, $2}' | cut -d',' -f1)
        MSG=$(echo "$CURRENT_LINE" | cut -d' ' -f3-)
        echo -e "\r\033[K${BLUE}[$(date +'%H:%M:%S')]${NC} $MSG"
        LAST_LINE="$CURRENT_LINE"
        STUCK_COUNTER=0
    else
        STUCK_COUNTER=$((STUCK_COUNTER + 1))
        # 每 30 秒打印一次心跳
        if [[ $STUCK_COUNTER -ge 30 ]]; then
            echo -e "\r\033[K${BLUE}[$(date +'%H:%M:%S')]${NC} ... 升级进行中（服务 active，等待日志更新）"
            STUCK_COUNTER=0
        fi
    fi

    sleep 1
done

# ============ 升级完成，检查结果 ============
echo ""
log "=== 升级服务结束，检查结果 ==="

FINAL_LOG=$(tail -5 "$LOG_FILE" 2>/dev/null || true)
if echo "$FINAL_LOG" | grep -qE "confirmRestart|PostCleanup|postInstallScript"; then
    log "升级流程已执行完毕 ✓"
elif echo "$FINAL_LOG" | grep -qiE "error|abort|fail"; then
    warn "日志末尾有错误信号，请检查 $LOG_FILE"
    echo "$FINAL_LOG"
else
    info "升级流程结束，请验证"
fi

# 检查版本是否变化
NEW_RELEASE=$(lsb_release -rs 2>/dev/null || echo "unknown")
if [[ "$NEW_RELEASE" == "$NEXT_RELEASE" ]]; then
    log "版本已更新: $CUR_RELEASE -> $NEW_RELEASE ✓"
else
    warn "版本仍是 $NEW_RELEASE（预期 $NEXT_RELEASE），升级可能未完成"
fi

# ============ 触发重启 ============
echo ""
log "=== 触发重启以加载新内核 ==="
warn "3 秒后重启，SSH 将断开，约 1-2 分钟后恢复"
echo ""
echo "重连命令:"
echo "  ssh root@${SERVER_IP}"
echo ""
echo "重连后验证:"
echo "  $0 --verify"
echo ""

# 用 systemd-run 调度重启（脱离当前会话）
systemd-run --on-active=3 --unit=delayed-reboot reboot

sleep 5
echo "如果看到这行，重启未触发，请手动执行: reboot"
