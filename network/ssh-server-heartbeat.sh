#!/bin/bash
sed -i -E 's/#?ClientAliveInterval.*/ClientAliveInterval 30/g' /etc/ssh/sshd_config
sed -i -E 's/#?ClientAliveCountMax.*/ClientAliveCountMax 6/g' /etc/ssh/sshd_config
# Debian/Ubuntu 服务名为 ssh, RHEL/CentOS 为 sshd
systemctl restart sshd 2>/dev/null || systemctl restart ssh