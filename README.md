# linux-toolkit

## How to use / 使用说明

Just copy and paste to your shell, Press [Enter] and the config will be automatically deployed.

将脚本复制粘贴到终端，按 [Enter] 即可自动部署。

---

## Setup zram (systemd required) / 配置 zram（需 systemd）

[More info / 详情](https://github.com/motao123/linux-toolkit/tree/main/system/zram)

---

## Using DoH Service / 使用 DoH 服务

### Cloudflare
```
bash -c "$(wget -qO - https://github.com/motao123/linux-toolkit/raw/main/network/dns-over-https/cloudflare.sh)"
```

---

## Enable BBR / 启用 BBR

### For CentOS 7
```
bash -c "$(wget -qO - https://github.com/motao123/linux-toolkit/raw/main/network/bbr/centos7.sh)"
```

---

## System Upgrade / 系统升级

### Ubuntu LTS (20.04 -> 22.04 -> 24.04)

```
wget -O ubuntu.sh https://github.com/motao123/linux-toolkit/raw/main/system-upgrade/ubuntu.sh
chmod +x ubuntu.sh
./ubuntu.sh
```

Options / 可选参数:
- `--yes` : Skip confirmation / 跳过确认
- `--verify` : Check result after reboot / 重启后验证升级结果
- `--help` : Show help / 显示帮助

Notes / 注意事项:
- Takes 30-60 minutes, SSH will disconnect 3-5 min during upgrade / 耗时 30-60 分钟，升级中 SSH 会断连 3-5 分钟
- Snapshot your server before upgrading / 升级前请打系统快照

### Debian (9 -> 10 -> 11 -> 12)

```
wget -O debian.sh https://github.com/motao123/linux-toolkit/raw/main/system-upgrade/debian.sh
chmod +x debian.sh
./debian.sh
```
