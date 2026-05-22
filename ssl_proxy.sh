#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}${BOLD}│      Caddy + Cloudflare 反代追加部署脚本         │${NC}"
echo -e "${BLUE}${BOLD}└──────────────────────────────────────────────────┘${NC}"

# 创建目录
mkdir -p /etc/caddy/ssl

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ==================== 1. 基础依赖 ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 1/4] 检查依赖...${NC}"
for cmd in curl tar wget git openssl jq gpg; do
    if ! check_cmd "$cmd"; then
        apt update -y && apt install -y curl tar wget git openssl jq psmisc debian-keyring debian-archive-keyring apt-transport-https
        break
    fi
done

# ==================== 2. Caddy 及插件 ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 2/4] Caddy 环境...${NC}"
if ! check_cmd "caddy"; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update -y && apt install -y caddy
fi

if ! /usr/bin/caddy list-modules | grep -q "dns.providers.cloudflare"; then
    /usr/bin/caddy add-package github.com/caddy-dns/cloudflare
fi

# ==================== 3. 参数与证书 ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 3/4] 参数收集...${NC}"
read -p " 输入域名: " DOMAIN
read -p " 输入后端反代地址 (例 127.0.0.1:8080): " BACKEND

CERT_FILE="/etc/caddy/ssl/${DOMAIN}_fullchain.pem"
KEY_FILE="/etc/caddy/ssl/${DOMAIN}_privkey.pem"
USE_EXISTING_CERT=false

# 扫描本地证书逻辑已保留
for cert in /etc/letsencrypt/live/"$DOMAIN"/fullchain.pem /root/.acme.sh/"${DOMAIN}"_ecc/fullchain.cer; do
    if [ -s "$cert" ]; then
        ln -sf "$cert" "$CERT_FILE"
        ln -sf "${cert/fullchain.cer/key}" "${cert/fullchain.pem/privkey.pem}" "$KEY_FILE" 2>/dev/null
        USE_EXISTING_CERT=true; break
    fi
done

if [ "$USE_EXISTING_CERT" = false ]; then
    read -p " 是否手动粘贴证书(y/n)? " P_CERT
    if [[ "$P_CERT" =~ ^[Yy] ]]; then
        echo "请粘贴证书内容后输入EOF:"
        while IFS= read -r line; do [[ "$line" == "EOF" ]] && break; echo "$line" >> "$CERT_FILE"; done
        echo "请粘贴私钥内容后输入EOF:"
        while IFS= read -r line; do [[ "$line" == "EOF" ]] && break; echo "$line" >> "$KEY_FILE"; done
        USE_EXISTING_CERT=true
    fi
fi

# ==================== 4. 追加 Caddyfile ====================
echo -e "\n${BLUE}${BOLD}▶ [步骤 4/4] 追加配置...${NC}"

if [ "$USE_EXISTING_CERT" = true ]; then
    cat <<EOF >> /etc/caddy/Caddyfile

$DOMAIN {
    tls $CERT_FILE $KEY_FILE
    reverse_proxy $BACKEND {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}
EOF
else
    read -p " 输入 CF API Token: " CF_TOKEN
    cat <<EOF >> /etc/caddy/Caddyfile

$DOMAIN {
    tls {
        dns cloudflare $CF_TOKEN
    }
    reverse_proxy $BACKEND {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}
EOF
fi

systemctl reload caddy
echo -e "${GREEN}${BOLD}🎉 部署完成，配置已追加至 /etc/caddy/Caddyfile${NC}"
