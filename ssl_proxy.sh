#!/bin/bash

# 检查权限
if [ "$EUID" -ne 0 ]; then echo "请使用 root 权限运行"; exit; fi

echo "--- 正在初始化环境 ---"
apt update && apt install -y caddy openssl curl

# 1. 基础配置输入
read -p "请输入全局 HTTP 端口: " g_http_port
read -p "请输入全局 HTTPS 端口: " g_https_port
read -p "请输入域名 (例如: komari.123panel.ccwu.cc): " domain
read -p "请输入端口: " port
domain_with_port="$domain:$port"
read -p "请输入反代目标端口 (例如: 25774): " target_port

# 2. 智能搜索证书
echo "正在检索系统证书..."
found_cert=""
found_key=""
# 搜索常见目录
search_paths=("/etc/ssl" "/etc/letsencrypt" "/root" "/home" "/var/www" "/etc/caddy")

for path in "${search_paths[@]}"; do
    if [ -d "$path" ]; then
        cert_file=$(find "$path" -type f \( -name "*$domain*.cer" -o -name "*$domain*.crt" -o -name "*$domain*.pem" \) -print -quit 2>/dev/null)
        if [ -n "$cert_file" ]; then
            if openssl x509 -in "$cert_file" -noout -checkend 0 &>/dev/null; then
                found_cert="$cert_file"
                key_dir=$(dirname "$cert_file")
                found_key=$(find "$key_dir" -type f -name "*$domain*.key" -o -name "*.key" -print -quit 2>/dev/null)
                [ -n "$found_key" ] && break
            fi
        fi
    fi
done

if [ -z "$found_cert" ] || [ -z "$found_key" ]; then
    echo "未检索到有效证书，请手动输入路径："
    read -p "证书路径: " found_cert
    read -p "私钥路径: " found_key
fi

# 3. 生成 Caddyfile
cat <<EOF > /etc/caddy/Caddyfile
{
    http_port $g_http_port
    https_port $g_https_port
}

$domain_with_port {
    reverse_proxy 127.0.0.1:$target_port
    tls $found_cert $found_key
}
EOF

# 4. 检查并开启自启动
echo "检查 Caddy 服务状态..."
if ! systemctl is-enabled caddy &>/dev/null; then
    echo "Caddy 未设置开机自启，正在配置..."
    systemctl enable caddy
fi

# 5. 重启并验证
echo "正在应用配置..."
caddy validate --config /etc/caddy/Caddyfile
if [ $? -eq 0 ]; then
    systemctl restart caddy
    echo "---------------------------------------"
    echo "部署成功！"
    echo "配置路径: /etc/caddy/Caddyfile"
    echo "域名: $domain_with_port"
    echo "状态: $(systemctl is-active caddy)"
    echo "自启: $(systemctl is-enabled caddy)"
    echo "---------------------------------------"
else
    echo "错误：配置语法检查失败，请检查 Caddyfile。"
fi
