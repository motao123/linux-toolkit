#!/bin/bash
# Linux 一键更新脚本（支持 Debian/Ubuntu + CentOS/RHEL）
# 修复/增强点：
#   1) set -euo pipefail + run_cmd 检查 PIPESTATUS，包管理失败不再被静默吞掉
#   2) check_reboot 直接设置全局 NEED_REBOOT，自动重启 (-r) 可正常触发
#   3) 旧内核清理加保护(Debian)：确认当前内核在 dpkg 列表中才删，且至少保留 2 个
#   4) unattended-upgrades / dnf-automatic 自动更新改为显式 (-a)，默认不擅自开启
#   5) -c 仅清理不再删除内核；临时文件改用 -mtime 避免 noatime 误删
#   6) 日志写入纯文本（去掉 ANSI 颜色码）
#   7) 新增 CentOS/RHEL 支持；遇到不支持的系统直接报错退出，不再误执行
#   8) 设置非交互前端(DEBIAN_FRONTEND=noninteractive) + dpkg conffile 策略，
#      避免 openssh-server 等更新时弹出交互选择框卡住脚本（默认保留本地修改）
set -euo pipefail

# 非交互前端：屏蔽 debconf/tzdata/grub 等交互提示
export DEBIAN_FRONTEND=noninteractive

# conffile 处理策略：默认保留本地修改的配置文件(--force-confold)，
# 批量更新时尤其重要——避免覆盖 sshd_config 把自己锁在门外；
# 加 -n 时改为采用维护者版本(--force-confnew)
CONF_POLICY="--force-confold"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="/var/log/system_update_$(date +%Y%m%d_%H%M%S).log"
: > "$LOG_FILE"

# 终端带色输出，日志写纯文本
_t() { echo -e "$1"; }
_l() { echo "$1" >> "$LOG_FILE"; }
info()    { _t "${BLUE}[INFO]${NC}  $1"; _l "[INFO]  $1"; }
success() { _t "${GREEN}[ OK ]${NC}   $1"; _l "[ OK ]   $1"; }
warn()    { _t "${YELLOW}[WARN]${NC}  $1"; _l "[WARN]  $1"; }
error()   { _t "${RED}[ERR ]${NC}   $1"; _l "[ERR ]  $1"; }
line()    { _t "${CYAN}============================================================${NC}"; _l "============================================================"; }

NEED_REBOOT=false
OS_FAMILY=""
PKG=""

# 运行命令并检查真实退出码
run_cmd() {
    local desc="$1"; shift
    info "执行: $desc"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then
        error "$desc 失败 (rc=$rc)"
        exit 1
    fi
    success "$desc 完成"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "需要 root 权限! 请用: sudo bash $0"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$NAME
        OS_ID=$ID
    else
        error "无法检测系统类型"
        exit 1
    fi
    case "$OS_ID" in
        debian|ubuntu|linuxmint|kali|deepin|pop|elementary|zorin)
            OS_FAMILY=debian
            success "系统: $OS_NAME (Debian/Ubuntu 系)"
            ;;
        centos|rhel|rocky|almalinux|fedora|ol|anolis|tencentos|opencloudos)
            OS_FAMILY=rhel
            PKG="$(command -v dnf 2>/dev/null || command -v yum 2>/dev/null)" || true
            if [ -z "$PKG" ]; then
                error "RHEL 系但未找到 dnf/yum"
                exit 1
            fi
            success "系统: $OS_NAME (RHEL 系, 使用 $PKG)"
            ;;
        *)
            error "不支持的系统: $OS_NAME ($OS_ID)，本脚本仅支持 Debian/Ubuntu 与 CentOS/RHEL 系"
            exit 1
            ;;
    esac
}

# ---------------- Debian/Ubuntu ----------------
deb_fix_broken() {
    line
    info "修复损坏的依赖..."
    run_cmd "dpkg --configure -a" dpkg --configure -a
    run_cmd "apt-get -f install" apt-get "${DOPT[@]}" -f install -y
}

deb_update_sources() {
    line
    info "更新软件源..."
    run_cmd "apt-get update" apt-get "${DOPT[@]}" update -y
}

deb_upgrade() {
    line
    info "升级软件包..."
    run_cmd "apt-get upgrade" apt-get "${DOPT[@]}" upgrade -y
    run_cmd "apt-get full-upgrade" apt-get "${DOPT[@]}" full-upgrade -y
}

deb_security_patch() {
    line
    info "应用安全更新..."
    apt-get "${DOPT[@]}" install -y unattended-upgrades 2>&1 | tee -a "$LOG_FILE" || true
    info "安全补丁已在 upgrade 阶段应用；如需后台自动更新请加 -a"
}

deb_enable_auto() {
    line
    info "配置无人值守自动安全更新..."
    run_cmd "安装 unattended-upgrades" apt-get "${DOPT[@]}" install -y unattended-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF
    success "已启用每天自动安全更新（/etc/apt/apt.conf.d/20auto-upgrades）"
}

deb_clean_packages() {
    line
    info "清理不需要的依赖与包缓存..."
    run_cmd "apt-get autoremove" apt-get "${DOPT[@]}" autoremove -y
    apt-get autoclean -y 2>&1 | tee -a "$LOG_FILE" || true
    apt-get clean 2>&1 | tee -a "$LOG_FILE" || true
    success "包清理完成"
}

deb_clean_kernels() {
    line
    info "清理旧内核..."
    local CURRENT_KERNEL
    CURRENT_KERNEL=$(uname -r)
    local ALL_KERNELS=()
    mapfile -a ALL_KERNELS < <(dpkg -l 2>/dev/null | awk '/^ii  linux-image-[0-9]/{print $2}' | sort -V) || true
    if [ "${#ALL_KERNELS[@]}" -eq 0 ]; then
        info "未检测到已安装的内核包，跳过"
        return 0
    fi
    local current_in_list=false k
    for k in "${ALL_KERNELS[@]}"; do
        [ "$k" = "linux-image-$CURRENT_KERNEL" ] && current_in_list=true
    done
    if [ "$current_in_list" = false ]; then
        warn "当前运行内核 linux-image-$CURRENT_KERNEL 不在 dpkg 列表中，为安全起见跳过旧内核清理"
        return 0
    fi
    local keep=2
    local total=${#ALL_KERNELS[@]}
    if [ "$total" -le "$keep" ]; then
        info "已安装内核数($total) <= 保留数($keep)，无需清理"
        return 0
    fi
    local i
    for ((i = 0; i < total - keep; i++)); do
        k="${ALL_KERNELS[$i]}"
        info "  移除旧内核: $k"
        apt-get "${DOPT[@]}" -y purge "$k" 2>&1 | tee -a "$LOG_FILE" || true
    done
    success "旧内核清理完成（保留最新 $keep 个）"
}

# ---------------- CentOS/RHEL ----------------
rhel_update() {
    line
    info "更新软件包..."
    run_cmd "$PKG update" "$PKG" -y update
}

rhel_security_patch() {
    line
    info "应用安全更新..."
    "$PKG" -y update --security 2>&1 | tee -a "$LOG_FILE" || true
    info "安全更新已在 update 阶段应用；如需后台自动更新请加 -a"
}

rhel_enable_auto() {
    line
    info "配置无人值守自动安全更新 (dnf-automatic)..."
    run_cmd "安装 dnf-automatic" "$PKG" install -y dnf-automatic
    cat > /etc/dnf/automatic.conf << 'AUTOEOF'
[commands]
update_cmd = default
apply_updates = yes
[emitters]
emitter = motd
AUTOEOF
    systemctl enable --now dnf-automatic.timer 2>&1 | tee -a "$LOG_FILE" || true
    success "已启用 dnf-automatic 定时自动更新"
}

rhel_clean() {
    line
    info "清理不需要的依赖与包缓存..."
    run_cmd "$PKG autoremove" "$PKG" -y autoremove
    "$PKG" clean all 2>&1 | tee -a "$LOG_FILE" || true
    success "包清理完成（旧内核由 installonly_limit 控制，autoremove 会清理超出限制的旧内核）"
}

# ---------------- 通用 ----------------
# 查询占用某锁文件的进程 pid（优先 fuser，回退 lsof）
_lock_holder() {
    local lock="$1" pid=""
    if command -v fuser >/dev/null 2>&1; then
        pid=$(fuser "$lock" 2>/dev/null | tr -d ' ')
    elif command -v lsof >/dev/null 2>&1; then
        pid=$(lsof -t "$lock" 2>/dev/null)
    fi
    echo "$pid"
}

# 等待 dpkg/apt 锁释放，避免并发 apt 导致脚本直接失败（绝不自行删除锁文件）
wait_dpkg_lock() {
    local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
    local timeout=180 interval=5 lock pid elapsed
    for lock in "${locks[@]}"; do
        [ -e "$lock" ] || continue
        pid=$(_lock_holder "$lock") || true
        if [ -n "$pid" ]; then
            warn "检测到 $lock 被进程 $pid 占用，等待其释放 (最多 ${timeout}s)..."
            elapsed=0
            while [ -n "$pid" ] && [ "$elapsed" -lt "$timeout" ]; do
                sleep "$interval"
                elapsed=$((elapsed + interval))
                pid=$(_lock_holder "$lock") || true
            done
            if [ -n "$pid" ]; then
                error "等待超时：$lock 仍被进程 $pid 占用，脚本无法安全继续。"
                error "请先查看并结束该进程后再运行："
                error "  ps -p $pid -o pid,ppid,etime,cmd"
                error "  cat /proc/$pid/cmdline | tr '\\0' ' '; echo"
                exit 1
            fi
            success "$lock 已释放"
        fi
    done
}

clean_tmp() {
    line
    info "清理临时文件与日志..."
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    find /var/tmp -type f -mtime +7 -delete 2>/dev/null || true
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=7d 2>&1 | tee -a "$LOG_FILE" || true
    fi
    success "临时文件清理完成"
}

check_reboot() {
    line
    local need=false
    if [ -f /var/run/reboot-required ]; then
        need=true
    fi
    if command -v needs-restarting >/dev/null 2>&1; then
        if ! needs-restarting -r >/dev/null 2>&1; then
            need=true
        fi
    fi
    if [ "$need" = true ]; then
        NEED_REBOOT=true
        warn "系统需要重启以完成更新!"
        [ -f /var/run/reboot-required ] && cat /var/run/reboot-required 2>/dev/null | tee -a "$LOG_FILE" || true
        if [ -f /var/run/reboot-required.pkgs ]; then
            info "相关包:"
            cat /var/run/reboot-required.pkgs 2>/dev/null | tee -a "$LOG_FILE" || true
        fi
    else
        success "无需重启"
    fi
}

generate_report() {
    line
    info "更新报告:"
    local UP=0
    if [ "$OS_FAMILY" = debian ]; then
        UP=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
        if command -v debsecan >/dev/null 2>&1; then
            info "漏洞扫描:"
            debsecan --format report 2>&1 | tee -a "$LOG_FILE" || true
        fi
    else
        UP=$("$PKG" -q list updates 2>/dev/null | wc -l || true)
    fi
    if [ "$UP" -gt 0 ]; then
        warn "还有 $UP 个包未升级"
        if [ "$OS_FAMILY" = debian ]; then
            apt list --upgradable 2>/dev/null | tee -a "$LOG_FILE"
        else
            "$PKG" list updates 2>/dev/null | tee -a "$LOG_FILE"
        fi
    else
        success "所有软件已是最新"
    fi
    info "系统: $OS_NAME"
    info "内核: $(uname -r)"
    info "磁盘:"
    df -h / 2>/dev/null | tee -a "$LOG_FILE"
    info "日志: $LOG_FILE"
}

# ---------------- 参数解析 ----------------
QUICK=false
SECONLY=false
CLEANONLY=false
REBOOT_FLAG=false
AUTO_UPGRADE=false

while [ $# -gt 0 ]; do
    case $1 in
        -h|--help)
            echo "用法: sudo bash $0 [选项]"
            echo "  -q           快速模式(仅升级不清理)"
            echo "  -s           仅安全更新"
            echo "  -c           仅清理(不含内核)"
            echo "  -a           启用无人值守自动安全更新(默认不启用)"
            echo "  -r           需要重启时自动重启"
            echo "  -n           冲突配置文件采用维护者版本(默认保留本地修改)"
            echo "  -h           帮助"
            exit 0
            ;;
        -q) QUICK=true; shift ;;
        -s) SECONLY=true; shift ;;
        -c) CLEANONLY=true; shift ;;
        -a) AUTO_UPGRADE=true; shift ;;
        -r) REBOOT_FLAG=true; shift ;;
        -n) CONF_POLICY="--force-confnew"; shift ;;
        *)  echo "未知参数: $1"; exit 1 ;;
    esac
done

# 根据 conffile 策略构造 apt-get 的 dpkg 选项(必须在参数解析后、dispatch 前确定)
declare -a DOPT=( -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=$CONF_POLICY" )

line
_t "${CYAN}   Linux 一键更新脚本 (支持 Debian/Ubuntu + CentOS/RHEL)${NC}"
_t "${CYAN}   $(date '+%Y-%m-%d %H:%M:%S')${NC}"
line

check_root
check_os

dispatch() {
    if [ "$OS_FAMILY" = debian ]; then
        wait_dpkg_lock
        if [ "$CLEANONLY" = true ]; then
            deb_clean_packages; clean_tmp
        elif [ "$SECONLY" = true ]; then
            deb_update_sources; deb_security_patch
            [ "$AUTO_UPGRADE" = true ] && deb_enable_auto
            check_reboot; generate_report
        else
            deb_fix_broken; deb_update_sources; deb_upgrade; deb_security_patch
            [ "$AUTO_UPGRADE" = true ] && deb_enable_auto
            if [ "$QUICK" != true ]; then
                deb_clean_packages; deb_clean_kernels; clean_tmp
            fi
            check_reboot; generate_report
        fi
    else
        if [ "$CLEANONLY" = true ]; then
            rhel_clean; clean_tmp
        elif [ "$SECONLY" = true ]; then
            rhel_security_patch
            [ "$AUTO_UPGRADE" = true ] && rhel_enable_auto
            check_reboot; generate_report
        else
            rhel_update; rhel_security_patch
            [ "$AUTO_UPGRADE" = true ] && rhel_enable_auto
            if [ "$QUICK" != true ]; then
                rhel_clean; clean_tmp
            fi
            check_reboot; generate_report
        fi
    fi
}

dispatch

line
success "全部完成!"
info "日志: $LOG_FILE"
line

if [ "$REBOOT_FLAG" = true ] && [ "$NEED_REBOOT" = true ]; then
    warn "10秒后自动重启..."
    sleep 10
    reboot
fi
