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

## VPS Small/Big Packet Test / VPS 大小包优化测试

Interactive test that compares small vs. large ICMP packets (latency, loss, mtr route, optional iperf3) to detect provider QoS / "小包优化" on a VPS. Generates a scored report and saves all logs to a local directory.

交互式测试脚本，对比小包/大包的延迟、丢包、mtr 路由及（可选的）iperf3 吞吐，用于检测 VPS 服务商是否存在大小包差异化限速（小包优化/丢包大包），自动生成评分报告并保存原始日志。

```
wget -O vps_packet_test.sh https://github.com/motao123/linux-toolkit/raw/main/network/vps_packet_test.sh
chmod +x vps_packet_test.sh
./vps_packet_test.sh
```

### Usage / 使用方法

Run directly and follow the interactive prompts / 直接运行，按交互提示输入即可:

| Prompt / 提示 | Default / 默认 | Description / 说明 |
|---|---|---|
| 目标 IP 或域名 | (必填) | Target IP or domain to test |
| Ping 测试次数 | 20 | Number of ping packets per size |
| 大包 ping 大小 | 1400 | Large packet size in bytes (ICMP payload) |
| 小包 ping 大小 | 56 | Small packet size in bytes (ICMP payload) |
| 是否运行 iperf3 | n | Throughput test, requires `iperf3 -s` running on target |
| 是否运行 mtr 路由对比 | y | Route comparison between small/big packets |

All tests run automatically after confirmation. Results (ping/mtr/iperf3 logs + `report.txt`) are saved to `./vps_test_<目标>_<时间>/`.

确认配置后自动依次执行所有测试，结果（ping/mtr/iperf3 日志 + `report.txt` 报告）保存在 `./vps_test_<目标>_<时间>/` 目录中。

### Rating / 评级说明

| Level / 等级 | Meaning / 含义 |
|---|---|
| Lv.0 无明显优化 | Small/big packets behave consistently / 大小包表现一致 |
| Lv.1 轻度嫌疑 | Minor anomaly, could be jitter, retest advised / 轻微异常，建议多测几次 |
| Lv.2 中度嫌疑 | Likely targeted QoS on large traffic / 大概率存在针对性限速 |
| Lv.3 重度嫌疑 | Confirmed differentiation, ping data unreliable / 基本确认存在优化 |

Dependencies / 依赖: `ping`, `mtr` (`mtr-tiny`), `iperf3` (optional / 可选). macOS: `brew install mtr iperf3`; Debian/Ubuntu: `sudo apt install mtr-tiny iperf3`.

Note / 注意: `mtr` may need root on Linux / Linux 下 mtr 可能需要 root 权限（`sudo ./vps_packet_test.sh`）。

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
