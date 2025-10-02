#!/usr/bin/env bash
set -euo pipefail

# xray_auto_menu.sh
# 一键智能安装 Xray + 生成 Clash config
# 支持 Cloudflare 代理 / DNS-only / Webroot / Standalone / 自签 / 无 TLS

# ---------- helpers ----------
info(){ echo -e "\e[1;34m[INFO]\e[0m $*"; }
ok(){ echo -e "\e[1;32m[OK]\e[0m $*"; }
warn(){ echo -e "\e[1;33m[WARN]\e[0m $*"; }
err(){ echo -e "\e[1;31m[ERR]\e[0m $*"; }
pause(){ read -rp "$*"; }

# ensure root
if [ "$EUID" -ne 0 ]; then
  err "请以 root 运行：sudo bash $0"
  exit 1
fi

# detect os family & package manager
PKG_INSTALL=""
UPDATE_CMD=""
OS_FAMILY=""
if [ -f /etc/debian_version ]; then
  OS_FAMILY="debian"
  PKG_INSTALL="apt -y install"
  UPDATE_CMD="apt update -y"
elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ]; then
  OS_FAMILY="rhel"
  if command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL="dnf -y install"
    UPDATE_CMD="dnf -y makecache"
  else
    PKG_INSTALL="yum -y install"
    UPDATE_CMD="yum makecache -y"
  fi
else
  warn "未识别系统，只尝试安装常见工具，可能存在兼容问题。"
  PKG_INSTALL="apt -y install || yum -y install"
  UPDATE_CMD="true"
fi

# install deps
info "更新包管理器并安装依赖..."
$UPDATE_CMD
if [ "$OS_FAMILY" = "debian" ]; then
  $PKG_INSTALL curl wget unzip socat lsof python3 python3-pip ca-certificates openssl cron jq net-tools dnsutils idn
else
  $PKG_INSTALL curl wget unzip socat lsof python3 python3-pip ca-certificates openssl cronie jq net-tools bind-utils || true
  if ! command -v idn >/dev/null 2>&1; then
    $PKG_INSTALL libidn || true
  fi
fi
ok "依赖安装/检查完成"

# get public ip
PUB_IP=$(curl -s https://ipv4.icanhazip.com || curl -s https://ifconfig.me || true)
PUB_IP="${PUB_IP// /}"

# ---------- menu ----------
echo
info "请选择证书 / 域名 方案："
cat <<'MENU'
1) 有域名 + Cloudflare DNS
2) 有域名 + Webroot
3) 有域名 + Standalone
4) 无域名 + 自签名证书
5) 无域名 + 无 TLS
MENU

read -rp "输入选项 [1-5]（默认1）: " CHOICE
CHOICE=${CHOICE:-1}

# common variables
read -rp "请输入备注名称（用于生成节点名，默认 MyServer）: " NODE_NAME
NODE_NAME=${NODE_NAME:-MyServer}

DOMAIN=""
CF_TOKEN=""
CF_EMAIL=""
WEBROOT=""
STOP_SERVICE_CMD=""
CF_MODE=1  # 默认走代理

if [ "$CHOICE" -eq 1 ]; then
  while [ -z "$DOMAIN" ]; do
    read -rp "请输入你的域名（例如 sub.example.com）： " DOMAIN
  done
  while [ -z "$CF_TOKEN" ]; do
    echo "请准备 Cloudflare API Token（Zone.DNS Edit 权限）"
    read -rp "请输入 Cloudflare API Token： " CF_TOKEN
  done
  read -rp "请输入 Cloudflare 邮箱（可留空）： " CF_EMAIL
  # 选择 Cloudflare 代理模式
  echo
  echo "请选择 Cloudflare 代理模式："
  echo "1) 走 Cloudflare 代理（橙云，隐藏真实 IP）"
  echo "2) 不走 Cloudflare 代理（DNS-only，直连服务器）"
  read -rp "输入选项 [1-2]（默认1）: " CF_MODE
  CF_MODE=${CF_MODE:-1}
  if [ "$CF_MODE" -eq 1 ]; then
    warn "已选择走 Cloudflare 代理（橙云）"
  else
    warn "已选择 DNS-only（直连服务器）"
  fi
elif [ "$CHOICE" -eq 2 ]; then
  while [ -z "$DOMAIN" ]; do
    read -rp "请输入你的域名（例如 sub.example.com）： " DOMAIN
  done
  while [ -z "$WEBROOT" ]; do
    read -rp "请输入 webroot 路径（例如 /var/www/html）： " WEBROOT
  done
elif [ "$CHOICE" -eq 3 ]; then
  while [ -z "$DOMAIN" ]; do
    read -rp "请输入你的域名（例如 sub.example.com）： " DOMAIN
  done
  warn "Standalone 模式会临时停止 80 端口占用程序（例如 nginx）"
  read -rp "如需停止 nginx，请输入 nginx，否则留空： " STOP_SERVICE_CMD
elif [ "$CHOICE" -eq 4 ]; then
  warn "使用自签名证书，客户端需要手动信任证书"
elif [ "$CHOICE" -eq 5 ]; then
  warn "无 TLS 模式，通信不加密，仅用于测试/内网"
else
  err "无效选项"; exit 1
fi

# ---------- install acme.sh ----------
if [[ "$CHOICE" =~ [1-4] ]]; then
  if [ ! -d "$HOME/.acme.sh" ]; then
    info "安装 acme.sh..."
    curl -sS https://get.acme.sh | bash
  else
    info "acme.sh 已存在，跳过安装"
  fi
  export PATH="$HOME/.acme.sh:$PATH"
fi

# ---------- certificate ----------
CERT_DIR=""
issue_cert_cloudflare(){
  export CF_Token="$CF_TOKEN"
  [ -n "$CF_EMAIL" ] && export CF_Email="$CF_EMAIL"
  info "注册 acme.sh 账户并使用 Let’s Encrypt..."
  ~/.acme.sh/acme.sh --register-account -m "${CF_EMAIL:-example@domain.com}" --server letsencrypt

  info "使用 Cloudflare DNS 模式申请证书..."
  ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --server letsencrypt --keylength ec-256 || true

  # 安装证书
  mkdir -p /etc/ssl/xray
  ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray 2>/dev/null || true"
}

issue_cert_webroot(){
  info "使用 Webroot 模式申请证书..."
  ~/.acme.sh/acme.sh --issue -d "$DOMAIN" -w "$WEBROOT" --server letsencrypt || true
  mkdir -p /etc/ssl/xray
  ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray 2>/dev/null || true"
}

issue_cert_standalone(){
  info "使用 Standalone 模式申请证书..."
  if [ -n "$STOP_SERVICE_CMD" ]; then
    systemctl stop "$STOP_SERVICE_CMD" || true
  fi
  ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --server letsencrypt || true
  mkdir -p /etc/ssl/xray
  ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray 2>/dev/null || true"
  if [ -n "$STOP_SERVICE_CMD" ]; then
    systemctl start "$STOP_SERVICE_CMD" || true
  fi
}

create_self_signed(){
  info "生成自签名证书到 /etc/ssl/xray/"
  mkdir -p /etc/ssl/xray
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout /etc/ssl/xray/xray.key -out /etc/ssl/xray/xray.crt \
    -subj "/CN=${DOMAIN:-$PUB_IP}"
}

case $CHOICE in
  1) issue_cert_cloudflare ;;
  2) issue_cert_webroot ;;
  3) issue_cert_standalone ;;
  4) create_self_signed ;;
  5) warn "无 TLS，跳过证书生成" ;;
esac

# ---------- verify cert ----------
if [ "$CHOICE" -ne 5 ] && [ ! -f /etc/ssl/xray/xray.crt ]; then
  err "证书未生成，请检查 acme.sh 日志或 Cloudflare Token 权限"
  exit 1
fi

# ---------- install Xray ----------
info "安装 Xray-core..."
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install >/dev/null 2>&1 || true
if ! command -v xray >/dev/null 2>&1; then
  err "Xray 安装失败，请手动检查"
  exit 1
fi
ok "Xray 安装完成"

# ---------- generate Xray config ----------
XRAY_DIR="/etc/xray"
mkdir -p "$XRAY_DIR"
UUID="$(cat /proc/sys/kernel/random/uuid)"
XRAY_PORT=$(( CHOICE==5 ? 12345 : 443 ))
TLS_ENABLED=$(( CHOICE!=5 ? 1 : 0 ))
WS_PATH="/websocket"

info "生成 Xray 配置 (VLESS+WS ${TLS_ENABLED:+with TLS}) ..."
cat > "$XRAY_DIR/config.json" <<JSON
{
  "log": {"loglevel":"warning"},
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": { "clients": [{ "id": "$UUID", "flow": "" }], "decryption": "none" },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH", "headers": { "Host": "${DOMAIN:-$PUB_IP}" } }$([ "$TLS_ENABLED" -eq 1 ] && cat <<'TLSBLOCK'
,
        "security": "tls",
        "tlsSettings": { "certificates": [{ "certificateFile": "/etc/ssl/xray/xray.crt", "keyFile": "/etc/ssl/xray/xray.key" }] }
TLSBLOCK
)
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
JSON

chmod 600 "$XRAY_DIR/config.json"
chown -R root:root "$XRAY_DIR"

# ---------- start Xray ----------
info "启用并启动 xray 服务..."
systemctl daemon-reload || true
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 2
if systemctl is-active --quiet xray; then
  ok "xray 已启动"
else
  err "xray 未能启动，请查看日志"
  journalctl -u xray --no-pager -n 200 || true
  exit 1
fi

# ---------- generate Clash config ----------
info "生成 Clash 配置到 /etc/clash/config.yaml ..."
CLASH_DIR="/etc/clash"
mkdir -p "$CLASH_DIR"
WS_PATH_ESCAPED=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote('$WS_PATH', safe=''))
PY)
SERVER_HOST="${DOMAIN:-$PUB_IP}"

cat > "$CLASH_DIR/config.yaml" <<YAML
port: 7890
socks-port: 7891
redir-port: 7892
allow-lan: true
mode: Rule
log-level: info
external-controller: 127.0.0.1:9091

proxies:
  - name: "$NODE_NAME"
    type: vless
    server: $SERVER_HOST
    port: $XRAY_PORT
    uuid: $UUID
    tls: $TLS_ENABLED
    network: ws
    udp: true
    ws-opts:
      path: $WS_PATH
      headers:
        Host: $SERVER_HOST

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - $NODE_NAME

rules:
  - DOMAIN-SUFFIX,netflix.com,Proxy
  - DOMAIN-SUFFIX,disneyplus.com,Proxy
  - DOMAIN-SUFFIX,primevideo.com,Proxy
  - DOMAIN-SUFFIX,hulu.com,Proxy
  - DOMAIN-SUFFIX,hbo.com,Proxy
  - DOMAIN-SUFFIX,openai.com,Proxy
  - DOMAIN-SUFFIX,chat.openai.com,Proxy
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
YAML

chmod 644 "$CLASH_DIR/config.yaml"

# ---------- expose config via HTTP ----------
info "启动本地 HTTP 服务 (9090) 暴露 Clash 配置..."
if command -v lsof >/dev/null 2>&1; then
  OLDPID=$(lsof -t -i:9090 || true)
  [ -n "$OLDPID" ] && kill -9 $OLDPID || true
fi
nohup python3 -m http.server 9090 --directory "$CLASH_DIR" >/dev/null 2>&1 &

# ---------- display info ----------
PUBLIC_DISPLAY="${DOMAIN:-$PUB_IP}"
ok "完成！关键信息："
echo "========================================"
if [ "$TLS_ENABLED" -eq 1 ]; then
  echo "协议: VLESS+WS+TLS"
  echo "域名/服务器: $PUBLIC_DISPLAY"
  echo "端口: $XRAY_PORT"
else
  echo "协议: VLESS+WS (无 TLS)"
  echo "服务器: $PUBLIC_DISPLAY"
  echo "端口: $XRAY_PORT"
fi
echo "UUID: $UUID"
echo "ws path: $WS_PATH"
echo
echo "Clash 订阅:"
echo "http://$PUBLIC_DISPLAY:9090/config.yaml"
echo
echo "手动节点 URI 示例:"
if [ "$TLS_ENABLED" -eq 1 ]; then
  echo "vless://$UUID@$PUBLIC_DISPLAY:$XRAY_PORT?type=ws&security=tls&path=$WS_PATH_ESCAPED&host=$PUBLIC_DISPLAY#$NODE_NAME"
else
  echo "vless://$UUID@$PUBLIC_DISPLAY:$XRAY_PORT?type=ws&security=none&path=$WS_PATH_ESCAPED&host=$PUBLIC_DISPLAY#$NODE_NAME"
fi
echo "Xray 配置文件: /etc/xray/config.json"
echo "Clash 配置文件: /etc/clash/config.yaml"
echo "查看 Xray 日志: journalctl -u xray -f"
echo "========================================"
