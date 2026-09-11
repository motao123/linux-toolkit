#!/bin/bash
echo "Begin" >> ~/wikihost_cloudflare_doh_install.log
download_tool_path=''
donwload_tool_args=''
arch='amd64'

# 按机器架构选择 cloudflared 二进制
case "$(uname -m)" in
    x86_64)  arch='amd64' ;;
    aarch64) arch='arm64' ;;
    armv7l|armv6l) arch='arm' ;;
    *) echo "ERROR: unsupported architecture: $(uname -m)"; exit 1 ;;
esac

find_download_tool(){
    if command -v wget &> /dev/null; then
        download_tool_path=$(command -v wget)
        donwload_tool_args=' --retry-connrefused --tries=0 -O '
        return
    fi;

    if command -v curl &> /dev/null; then
        download_tool_path=$(command -v curl)
        donwload_tool_args=' --retry-connrefused --retry 0 -o '
        return
    fi;

    __log "ERROR: download tool not found"
    exit
}

download_cloudflared(){
    # 始终拉取最新 release，避免硬编码版本号过期
    __run $download_tool_path $donwload_tool_args /tmp/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch
    mv -f /tmp/cloudflared /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
}

install_systemd_service(){
   echo "[Unit]
Description=Cloudflare DNS Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/local/bin/cloudflared proxy-dns

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/cloudflare-doh.service
    __run systemctl enable cloudflare-doh
}

change_resolv_conf(){
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
}

__run(){
    echo ' + "'"$@"'"'
    echo ' + "'"$@"'"' >> ~/wikihost_cloudflare_doh_install.log
    $@
}

__log(){
    echo '['`date '+%Y-%m-%d %H:%M:%S'`']'$1
    echo '['`date '+%Y-%m-%d %H:%M:%S'`']'$1 >> ~/wikihost_cloudflare_doh_install.log
}

[ ! -d "/usr/local/bin" ] && __log  "ERROR: /usr/local/bin not exists" && exit

__log "INFO: looking download tools (like curl/wget)..."
find_download_tool
__log "INFO: Found download tools on: $download_tool_path"
__log "INFO: Try to download cloudflared to /tmp..."
download_cloudflared
__log "INFO: Installing cloudflare dns-over-https as service..."
install_systemd_service
__log "INFO: Starting service..."
__run chattr -i /etc/resolv.conf
__run systemctl start cloudflare-doh
__log "INFO: Backuping /etc/resolv.conf to /etc/resolv.conf.bak"
/usr/bin/cp -f /etc/resolv.conf /etc/resolv.conf.bak
__log "INFO: Writing nameserver 1.1.1.1 into /etc/resolv.conf"
change_resolv_conf
__log "INFO: Locking /etc/resolv.conf"
__run chattr +i /etc/resolv.conf
__log "INFO: Cloudflare dns-over-https has been installed"
# 用 DNS 解析验证 DoH 是否生效（ping 需放行 ICMP，部分机器会误报）
if command -v getent >/dev/null 2>&1; then
    getent hosts google.com || (__log "ERROR: Cloudflare dns-over-https not working" && exit)
else
    ping -c 1 google.com || (__log "ERROR: Cloudflare dns-over-https not working" && exit)
fi
__log "INFO: Cloudflare dns-over-https has been installed and it's working"
