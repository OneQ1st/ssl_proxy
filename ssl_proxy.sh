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
echo -e "${BLUE}${BOLD}│     Caddy + Cloudflare 通用反代智能部署脚本      │${NC}"
echo -e "${BLUE}${BOLD}└──────────────────────────────────────────────────┘${NC}"

# 创建目录
mkdir -p /etc/caddy/ssl

# 检查命令函数
check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ==================== 1. 基础依赖检查 ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 1/5] 正在检查系统基础依赖环境...${NC}"
NEED_INSTALL=()
for cmd in curl tar wget git openssl jq gpg; do
    if ! check_cmd "$cmd"; then
        NEED_INSTALL+=("$cmd")
    fi
done

if [ ${#NEED_INSTALL[@]} -ne 0 ]; then
    echo -e "${YELLOW} ℹ 发现缺失依赖，正在安装... ${NC}"
    apt update -y && apt install -y curl tar wget git openssl jq psmisc debian-keyring debian-archive-keyring apt-transport-https
else
    echo -e "${GREEN} ✔ 基础依赖完整 ${NC}"
fi

# ==================== 2. Caddy + Cloudflare 插件检查 ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 2/5] 检查 Caddy 及 Cloudflare 插件...${NC}"

if ! check_cmd "caddy"; then
    echo -e "${YELLOW} ℹ 正在安装 Caddy... ${NC}"
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update -y && apt install -y caddy
fi

if ! /usr/bin/caddy list-modules | grep -q "dns.providers.cloudflare"; then
    echo -e "${YELLOW} ℹ 正在注入 Cloudflare 插件... ${NC}"
    /usr/bin/caddy add-package github.com/caddy-dns/cloudflare
fi

# ==================== 3. 参数收集 ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 3/5] 配置参数收集...${NC}"
read -p " 请输入您的域名: " DOMAIN
read -p " 请输入后端反代地址: " BACKEND
read -p " 请输入 HTTPS 端口 (默认 443): " EX_PORT
EX_PORT=${EX_PORT:-443}
read -p " 请输入邮箱: " MY_EMAIL

# ==================== 4. 生成 Caddy 配置 ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 4/5] 生成 Caddy 配置...${NC}"

cat <<EOF > /etc/caddy/Caddyfile
{
    email $MY_EMAIL
    http_port 80
    https_port $EX_PORT
}

$DOMAIN:$EX_PORT {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    reverse_proxy $BACKEND {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF

# 设置环境变量存放 Token
read -p " 请输入 Cloudflare API Token: " CF_TOKEN
mkdir -p /etc/systemd/system/caddy.service.d
echo "[Service]
Environment=CF_API_TOKEN=$CF_TOKEN" > /etc/systemd/system/caddy.service.d/cloudflare.conf

# ==================== 5. 服务启动 ====================
systemctl daemon-reload
systemctl enable --now caddy
systemctl restart caddy

echo -e "\n${GREEN}${BOLD}🎉 部署完成！${NC}"
echo -e "🌐 访问地址 → https://$DOMAIN:$EX_PORT"
