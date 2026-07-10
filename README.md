# How to use
Just copy and paste to your shell, Press [enter] and the config will be automatically deploy

## Setup zram (systemd required)
[More info](https://github.com/motao123/linux-toolkit/tree/main/system/zram)


## Using DoH Service
### Cloudflare
```
bash -c "$(wget -qO - https://github.com/motao123/linux-toolkit/raw/main/network/dns-over-https/cloudflare.sh)"
```
## Enable BBR
### For CentOS 7
```
bash -c "$(wget -qO - https://github.com/motao123/linux-toolkit/raw/main/network/bbr/centos7.sh)"
```

## System Upgrade
### Ubuntu LTS (20.04 -> 22.04 -> 24.04)
```
wget -O ubuntu.sh https://github.com/motao123/linux-toolkit/raw/main/system-upgrade/ubuntu.sh
chmod +x ubuntu.sh
./ubuntu.sh
```
Options: `--yes` skip confirmation, `--verify` check result after reboot.
