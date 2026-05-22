#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\033[0;32m====================================================\033[0m"
echo -e "\033[0;36m       通用 Nginx 反代配置生成 (保留全套证书逻辑)       \033[0m"
echo -e "\033[0;32m====================================================\033[0m"

# 1. 基础环境检查
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "${YELLOW}>>> 未检测到 Nginx，正在安装...${NC}"
    apt update -y && apt install -y nginx curl socat net-tools wget git ca-certificates psmisc
fi

# 2. 收集参数
read -p "请输入域名 (例如: example.com): " DOMAIN
read -p "请输入外部监听端口 (默认 443): " EX_PORT
EX_PORT=${EX_PORT:-443}
read -p "请输入反代目标地址 (例如: http://127.0.0.1:3000): " TARGET_URL
read -p "请输入邮箱 (用于 Let's Encrypt 通知): " MY_EMAIL

# 3. 安装/升级 acme.sh
ACME_DIR="$HOME/.acme.sh"
ACME_BIN="$ACME_DIR/acme.sh"

if [ ! -f "$ACME_BIN" ]; then
    echo -e "\033[0;33m>>> 正在安装 acme.sh...\033[0m"
    curl https://get.acme.sh | sh -s email="$MY_EMAIL"
fi
export PATH="$ACME_DIR:$PATH"
"$ACME_BIN" --upgrade --auto-upgrade

# 4. 完整的证书检测与申请逻辑
CERT_FILE="/etc/nginx/ssl_certs/${DOMAIN}_fullchain.pem"
KEY_FILE="/etc/nginx/ssl_certs/${DOMAIN}_privkey.pem"
mkdir -p /etc/nginx/ssl_certs

SKIP_CERT=false
POSSIBLE_CERTS=("$HOME/.acme.sh/${DOMAIN}_ecc/fullchain.cer" "/etc/letsencrypt/live/$DOMAIN/fullchain.pem")
POSSIBLE_KEYS=("$HOME/.acme.sh/${DOMAIN}_ecc/$DOMAIN.key" "/etc/letsencrypt/live/$DOMAIN/privkey.pem")

echo -e "\033[0;33m>>> 正在检测现有证书...\033[0m"
for idx in "${!POSSIBLE_CERTS[@]}"; do
    if [ -s "${POSSIBLE_CERTS[$idx]}" ] && [ -s "${POSSIBLE_KEYS[$idx]}" ]; then
        echo -e "${GREEN}>>> 发现匹配证书，正在复用...${NC}"
        ln -sf "${POSSIBLE_CERTS[$idx]}" "$CERT_FILE"
        ln -sf "${POSSIBLE_KEYS[$idx]}" "$KEY_FILE"
        SKIP_CERT=true; break
    fi
done

if [ "$SKIP_CERT" = false ]; then
    read -p "未发现匹配证书，是否手动提供路径？(y/n): " PROVIDE_CERT
    if [[ "$PROVIDE_CERT" =~ ^[Yy]$ ]]; then
        read -p "证书路径: " USER_CERT
        read -p "私钥路径: " USER_KEY
        ln -sf "$USER_CERT" "$CERT_FILE"
        ln -sf "$USER_KEY" "$KEY_FILE"
        SKIP_CERT=true
    else
        echo -e "\033[0;33m>>> 请选择申请方式: 1) Cloudflare DNS, 2) HTTP Standalone${NC}"
        read -p "选择 [1/2]: " AUTH_MODE
        if [ "$AUTH_MODE" == "1" ]; then
            read -p "请输入 Cloudflare Token: " CF_Key
            export CF_Token="$CF_Key"
            "$ACME_BIN" --issue --dns dns_cf -d "$DOMAIN" --ecc
        else
            systemctl stop nginx 2>/dev/null
            "$ACME_BIN" --issue -d "$DOMAIN" --standalone --httpport 80 --ecc
        fi
        "$ACME_BIN" --install-cert -d "$DOMAIN" --ecc \
            --fullchain-file "$CERT_FILE" \
            --key-file "$KEY_FILE" \
            --reloadcmd "systemctl reload nginx"
    fi
fi

# 5. 生成独立 Nginx 配置文件
CONFIG_PATH="/etc/nginx/conf.d/${DOMAIN}.conf"
cat <<NGINX_EOF > "$CONFIG_PATH"
server {
    listen $EX_PORT ssl;
    server_name $DOMAIN;

    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass $TARGET_URL;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX_EOF

# 6. 完成
nginx -t && systemctl restart nginx

echo -e "\033[0;32m====================================================\033[0m"
echo -e "配置已生成: $CONFIG_PATH"
echo -e "访问地址: https://$DOMAIN:$EX_PORT"
echo -e "\033[0;32m====================================================\033[0m"
