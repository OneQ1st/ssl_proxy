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
echo -e "\( {BLUE} \){BOLD}┌──────────────────────────────────────────────────┐${NC}"
echo -e "\( {BLUE} \){BOLD}│     Caddy + Cloudflare 通用反代智能部署脚本      │${NC}"
echo -e "\( {BLUE} \){BOLD}└──────────────────────────────────────────────────┘${NC}"

# 创建目录
mkdir -p /etc/caddy/ssl

# 检查命令函数
check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ==================== 1. 基础依赖检查 ====================
echo -e "\n\( {BLUE} \){BOLD}▶ [步骤 1/5] 正在检查系统基础依赖环境...${NC}"
NEED_INSTALL=()
for cmd in curl tar wget git openssl jq gpg; do
    if ! check_cmd "$cmd"; then
        NEED_INSTALL+=("$cmd")
    fi
done

if [ ${#NEED_INSTALL[@]} -ne 0 ]; then
    echo -e "\( {YELLOW} ℹ 发现缺失依赖，正在安装... \){NC}"
    apt update -y
    apt install -y curl tar wget git openssl jq psmisc debian-keyring debian-archive-keyring apt-transport-https
else
    echo -e "\( {GREEN} ✔ 基础依赖完整 \){NC}"
fi

# ==================== 2. Caddy + Cloudflare 插件检查 ====================
echo -e "\n\( {BLUE} \){BOLD}▶ [步骤 2/5] 检查 Caddy 及 Cloudflare 插件...${NC}"

CADDY_READY=false
if check_cmd "caddy"; then
    if /usr/bin/caddy list-modules | grep -q "dns.providers.cloudflare"; then
        echo -e "\( {GREEN} ✔ Caddy 已安装并集成 Cloudflare 插件 \){NC}"
        CADDY_READY=true
    else
        echo -e "\( {YELLOW} ℹ Caddy 已安装但缺少 Cloudflare 插件，正在补装... \){NC}"
    fi
fi

if [ "$CADDY_READY" = false ]; then
    if ! check_cmd "caddy"; then
        echo -e "\( {YELLOW} ℹ 正在安装 Caddy... \){NC}"
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt update -y && apt install -y caddy || { echo -e "\( {RED} ✖ Caddy 安装失败 \){NC}"; exit 1; }
    fi
    echo -e "\( {YELLOW} ℹ 正在注入 Cloudflare 插件... \){NC}"
    /usr/bin/caddy add-package github.com/caddy-dns/cloudflare || { echo -e "\( {RED} ✖ 插件注入失败 \){NC}"; exit 1; }
    echo -e "\( {GREEN} ✔ Caddy 及插件安装完成 \){NC}"
fi

# ==================== 3. 参数收集与证书智能扫描 ====================
echo -e "\n\( {BLUE} \){BOLD}▶ [步骤 3/5] 配置参数收集与证书扫描...${NC}"
echo -e "\( {BLUE}────────────────────────────────────────────────── \){NC}"

read -p " 请输入您的域名 (例如: example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "\( {RED} ✖ 域名不能为空！ \){NC}"; exit 1
fi

read -p " 请输入后端反代地址 (例如: 127.0.0.1:8080): " BACKEND
if [ -z "$BACKEND" ]; then
    echo -e "\( {RED} ✖ 后端地址不能为空！ \){NC}"; exit 1
fi

# 证书扫描
CERT_FILE="/etc/caddy/ssl/fullchain.pem"
KEY_FILE="/etc/caddy/ssl/privkey.pem"

POSSIBLE_CERTS=(
    "$CERT_FILE"
    "/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    "/etc/acme.sh/${DOMAIN}_ecc/fullchain.cer"
    "\( HOME/.acme.sh/ \){DOMAIN}_ecc/fullchain.cer"
    "\( HOME/.acme.sh/ \){DOMAIN}/fullchain.cer"
    "/root/.acme.sh/${DOMAIN}_ecc/fullchain.cer"
    "/etc/ssl/$DOMAIN/fullchain.pem"
)

POSSIBLE_KEYS=(
    "$KEY_FILE"
    "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    "/etc/acme.sh/${DOMAIN}_ecc/$DOMAIN.key"
    "\( HOME/.acme.sh/ \){DOMAIN}_ecc/$DOMAIN.key"
    "\( HOME/.acme.sh/ \){DOMAIN}/$DOMAIN.key"
    "/root/.acme.sh/${DOMAIN}_ecc/$DOMAIN.key"
    "/etc/ssl/$DOMAIN/privkey.pem"
)

USE_EXISTING_CERT=false

echo -e "\( {YELLOW} ℹ 正在扫描本地现有证书... \){NC}"
for idx in "${!POSSIBLE_CERTS[@]}"; do
    cert_path="${POSSIBLE_CERTS[$idx]}"
    key_path="${POSSIBLE_KEYS[$idx]}"
    if [ -s "$cert_path" ] && [ -s "$key_path" ]; then
        if openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -q "$DOMAIN"; then
            echo -e "${GREEN} ✔ 发现匹配证书: \( cert_path \){NC}"
            ln -sf "$cert_path" "$CERT_FILE"
            ln -sf "$key_path" "$KEY_FILE"
            USE_EXISTING_CERT=true
            break
        fi
    fi
done

# 未找到证书时允许手动提供
if [ "$USE_EXISTING_CERT" = false ]; then
    echo -e "\( {YELLOW} ℹ 未发现本地匹配证书 \){NC}"
    read -p " 是否手动提供证书？(y/n，默认 n): " PROVIDE_CERT
    
    if [[ "\( PROVIDE_CERT" =\~ ^[Yy](es)? \) ]]; then
        echo -e "\n 1) 输入文件路径   2) 直接粘贴证书内容"
        read -p " 请选择 [1/2]: " CERT_INPUT_MODE
        
        if [ "$CERT_INPUT_MODE" == "1" ]; then
            read -p " 证书路径: " USER_CERT
            read -p " 私钥路径: " USER_KEY
            if [ -s "$USER_CERT" ] && [ -s "$USER_KEY" ]; then
                ln -sf "$USER_CERT" "$CERT_FILE"
                ln -sf "$USER_KEY" "$KEY_FILE"
                USE_EXISTING_CERT=true
                echo -e "\( {GREEN} ✔ 证书导入成功 \){NC}"
            else
                echo -e "\( {RED} ✖ 文件不存在 \){NC}"
            fi
        elif [ "$CERT_INPUT_MODE" == "2" ]; then
            echo -e "\( {YELLOW}请粘贴证书内容（以 -----BEGIN 开头），结束后输入 EOF \){NC}"
            rm -f "$CERT_FILE"
            while IFS= read -r line; do
                [[ "$line" == "EOF" ]] && break
                echo "$line" >> "$CERT_FILE"
            done

            echo -e "\( {YELLOW}请粘贴私钥内容（以 -----BEGIN 开头），结束后输入 EOF \){NC}"
            rm -f "$KEY_FILE"
            while IFS= read -r line; do
                [[ "$line" == "EOF" ]] && break
                echo "$line" >> "$KEY_FILE"
            done

            if [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ] && openssl x509 -in "$CERT_FILE" -noout >/dev/null 2>&1; then
                USE_EXISTING_CERT=true
                echo -e "\( {GREEN} ✔ 证书粘贴并验证成功 \){NC}"
            else
                echo -e "\( {RED} ✖ 证书验证失败，将使用自动申请 \){NC}"
                rm -f "$CERT_FILE" "$KEY_FILE"
            fi
        fi
    fi
fi

# 其他参数
read -p " 请输入 HTTPS 端口 (默认 443): " EX_PORT
EX_PORT=${EX_PORT:-443}
read -p " 请输入 HTTP 端口 (默认 80): " HTTP_PORT
HTTP_PORT=${HTTP_PORT:-80}
read -p " 请输入邮箱 (用于证书通知): " MY_EMAIL

if [ "$USE_EXISTING_CERT" = false ]; then
    echo -e "\n 请选择证书申请方式:"
    echo -e "  1) Cloudflare DNS 挑战（推荐）"
    echo -e "  2) HTTP 挑战"
    read -p " 选择 [1/2]: " AUTH_MODE
fi

# ==================== 4. 生成 Caddy 配置（追加模式） ====================
echo -e "\n\( {BLUE} \){BOLD}▶ [步骤 4/5] 生成 Caddy 配置...${NC}"

CONFIG_FILE="/etc/caddy/Caddyfile"

if [ ! -f "$CONFIG_FILE" ]; then
    cat <<BASE > "$CONFIG_FILE"
{
    email $MY_EMAIL
    http_port $HTTP_PORT
    https_port $EX_PORT
}
BASE
    echo -e "\( {GREEN} ✔ 已创建新 Caddyfile \){NC}"
else
    echo -e "\( {YELLOW} ℹ 检测到已有 Caddyfile，正在追加配置 \){NC}"
fi

# 追加站点配置
if [ "$USE_EXISTING_CERT" = true ]; then
    cat <<SITE >> "$CONFIG_FILE"

$DOMAIN:$EX_PORT {
    tls $CERT_FILE $KEY_FILE

    reverse_proxy $BACKEND {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        flush_interval -1
    }
}
SITE
else
    if [ "$AUTH_MODE" == "1" ]; then
        read -p " 请输入 Cloudflare API Token: " CF_TOKEN
        cat <<SITE >> "$CONFIG_FILE"

$DOMAIN:$EX_PORT {
    tls {
        dns cloudflare $CF_TOKEN
    }

    reverse_proxy $BACKEND {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        flush_interval -1
    }
}
SITE
    else
        cat <<SITE >> "$CONFIG_FILE"

$DOMAIN:$EX_PORT {
    tls {
        acme_ca https://acme-v02.api.letsencrypt.org/directory
    }

    reverse_proxy $BACKEND {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        flush_interval -1
    }
}
SITE
    fi
fi

# ==================== 5. 服务启动 ====================
cat <<SVC > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now caddy >/dev/null 2>&1
systemctl restart caddy >/dev/null 2>&1

echo -e "\n\( {GREEN} \){BOLD}🎉 部署完成！${NC}"
echo -e "🌐 访问地址 → ${GREEN}https://\( DOMAIN \){NC}"
echo -e "📄 配置位置 → \( {BLUE}/etc/caddy/Caddyfile \){NC}"
echo -e "🔍 查看日志 → \( {YELLOW}journalctl -u caddy -f \){NC}"
