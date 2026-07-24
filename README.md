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

One script for both Debian/Ubuntu and CentOS/RHEL (package update + cleanup + reboot check).
一个脚本同时支持 Debian/Ubuntu 与 CentOS/RHEL（更新软件包 + 清理 + 重启检测）。

```
wget -O system_update.sh https://github.com/motao123/linux-toolkit/raw/main/system-upgrade/system_update.sh
chmod +x system_update.sh
sudo ./system_update.sh
```

Supported / 支持的系统:
- Debian / Ubuntu (apt)
- CentOS / RHEL / Rocky / AlmaLinux / Fedora / TencentOS / OpenCloudOS (dnf/yum)

Options / 可选参数:
- `-q` : Quick mode, skip cleanup / 快速模式（仅升级不清理）
- `-s` : Security update only / 仅安全更新
- `-c` : Cleanup only (keeps kernel) / 仅清理（不动内核）
- `-a` : Enable unattended auto security updates / 启用无人值守自动安全更新
- `-r` : Auto reboot if required / 需要重启时自动重启
- `-n` : Use maintainer's version on conffile conflict (default keeps local) / 配置文件冲突时采用维护者版本（默认保留本地修改）
- `-h` : Show help / 显示帮助

Notes / 注意事项:
- Non-interactive by default; locally modified configs (e.g. sshd_config) are kept / 默认非交互，保留本地修改的配置文件（如 sshd_config），避免被覆盖后无法登录
- Reboot-required packages (kernel, etc.) are detected; use `-r` to auto reboot / 会自动检测内核等需重启的包，加 `-r` 自动重启

> This script performs package updates, not a distro release upgrade.
> 本脚本执行软件包更新，不做发行版大版本升级（如需 LTS 升级请用 `do-release-upgrade`）。
