#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}${BOLD}│     Caddy + Cloudflare 反代追加部署脚本          │${NC}"
echo -e "${BLUE}${BOLD}└──────────────────────────────────────────────────┘${NC}"

# 参数收集
echo -e "\n${BLUE}${BOLD}▶ [步骤 1/3] 配置参数输入...${NC}"
read -p " 请输入域名: " DOMAIN
read -p " 请输入后端地址 (例: 127.0.0.1:8080): " BACKEND
read -p " 请输入 Cloudflare API Token: " CF_TOKEN
read -p " 请输入邮箱 (证书申请用): " MY_EMAIL

# 确保配置目录存在
mkdir -p /etc/caddy

# 追加站点配置到 Caddyfile
echo -e "\n${BLUE}${BOLD}▶ [步骤 2/3] 追加 Caddyfile 配置...${NC}"

# 使用 cat >> 追加配置
cat <<EOF >> /etc/caddy/Caddyfile

$DOMAIN {
    tls {
        dns cloudflare $CF_TOKEN
    }
    reverse_proxy $BACKEND {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF

echo -e "${GREEN} ✔ 配置已追加至 /etc/caddy/Caddyfile ${NC}"

# 重载 Caddy 服务
echo -e "\n${BLUE}${BOLD}▶ [步骤 3/3] 重载 Caddy 服务...${NC}"
systemctl reload caddy

if [ $? -eq 0 ]; then
    echo -e "${GREEN}${BOLD}🎉 部署成功！${NC}"
    echo -e "🌐 站点: https://$DOMAIN"
else
    echo -e "${RED} ✖ 服务重载失败，请检查配置文件: journalctl -u caddy --no-pager | tail -n 20 ${NC}"
fi
