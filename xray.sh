#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# xray_auto_menu.sh
# 一键智能安装 Xray + Clash 配置
# Cloudflare DNS 支持代理/直连选择
# 支持 Linux 主流系统
# ===========================================

info(){ echo -e "\e[1;34m[INFO]\e[0m $*"; }
ok(){ echo -e "\e[1;32m[OK]\e[0m $*"; }
warn(){ echo -e "\e[1;33m[WARN]\e[0m $*"; }
err(){ echo -e "\e[1;31m[ERR]\e[0m $*"; }

# ensure root
if [ "$EUID" -ne 0 ]; then
  err "请以 root 运行：sudo bash $0"
  exit 1
fi

# detect OS
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
  warn "未识别系统，仅尝试安装常用工具"
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
ok "依赖安装完成"

# get public IP
PUB_IP=$(curl -s https://ipv4.icanhazip.com || curl -s https://ifconfig.me || true)
PUB_IP="${PUB_IP// /}"

# menu
echo
info "请选择证书 / 域名 方案："
cat <<'MENU'
1) 有域名 + Cloudflare DNS（推荐）
2) 有域名 + Webroot（已有网站）
3) 有域名 + Standalone（临时停止 80 端口）
4) 无域名 + 自签名证书
5) 无域名 + 无 TLS
MENU

read -rp "输入选项 [1-5]（默认1）: " CHOICE
CHOICE=${CHOICE:-1}

# common variables
read -rp "请输入节点备注名称（默认 MyServer）: " NODE_NAME
NODE_NAME=${NODE_NAME:-MyServer}

# handle choices
DOMAIN=""
CF_TOKEN=""
CF_EMAIL=""
WEBROOT=""
STOP_SERVICE_CMD=""
CF_PROXY_MODE=""

if [ "$CHOICE" -eq 1 ]; then
  while [ -z "$DOMAIN" ]; do
    read -rp "请输入你的域名（例如 sub.example.com）： " DOMAIN
  done
  while [ -z "$CF_TOKEN" ]; do
    echo "请准备 Cloudflare API Token（Zone.DNS Edit 权限）"
    read -rp "请输入 Cloudflare API Token： " CF_TOKEN
  done
  read -rp "（可选）Cloudflare 账户邮箱： " CF_EMAIL

  echo
  echo "请选择 Cloudflare 代理模式："
  echo "1) 走 Cloudflare 代理（橙云，隐藏真实 IP）"
  echo "2) 不走 Cloudflare 代理（DNS-only，直连服务器）"
  read -rp "输入选项 [1-2]（默认1）: " CF_PROXY_CHOICE
  CF_PROXY_CHOICE=${CF_PROXY_CHOICE:-1}

  if [ "$CF_PROXY_CHOICE" -eq 1 ]; then
    CF_PROXY_MODE="proxied"
    warn "已选择走 Cloudflare 代理（橙云）"
  else
    CF_PROXY_MODE="dns_only"
    warn "已选择不走 Cloudflare 代理（直连模式）"
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
  warn "Standalone 模式会临时停止 80 端口占用程序"
  read -rp "如需停止 nginx，请输入 nginx，否则留空： " STOP_SERVICE_CMD

elif [ "$CHOICE" -eq 4 ]; then
  warn "使用自签名证书，客户端需手动信任证书"

elif [ "$CHOICE" -eq 5 ]; then
  warn "无 TLS 模式，仅用于测试/内网"
else
  err "无效选项"; exit 1
fi

# install acme.sh if needed
if [[ "$CHOICE" =~ ^[1-4]$ ]]; then
  if [ ! -d "$HOME/.acme.sh" ]; then
    info "安装 acme.sh..."
    curl -sS https://get.acme.sh | bash
  else
    info "acme.sh 已存在，跳过安装"
  fi
  export PATH="$HOME/.acme.sh:$PATH"
fi

# certificate functions
CERT_DIR=""
issue_cert_cloudflare(){
  # 确保邮箱不为空
  while [ -z "$CF_EMAIL" ]; do
    read -rp "请输入你的邮箱（用于 acme.sh 注册 Let’s Encrypt 账户）： " CF_EMAIL
  done

  # 注册账户并指定 CA 为 Let’s Encrypt
  info "注册 acme.sh 账户并使用 Let’s Encrypt..."
  ~/.acme.sh/acme.sh --register-account -m "$CF_EMAIL" --server letsencrypt

  # 设置 Cloudflare API Token
  export CF_Token="$CF_TOKEN"
  export CF_Email="$CF_EMAIL"

  info "使用 Cloudflare DNS 模式申请证书..."
  ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --yes-I-know-dns-manual-mode >/dev/null 2>&1 || \
  ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" || true

  # 检查证书目录
  if [ -d "$HOME/.acme.sh/${DOMAIN}_ecc" ]; then
    CERT_DIR="$HOME/.acme.sh/${DOMAIN}_ecc"
  else
    CERT_DIR="$HOME/.acme.sh/$DOMAIN"
  fi

  # 安装证书
  mkdir -p /etc/ssl/xray
  ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray 2>/dev/null || true" || true
}

issue_cert_webroot(){
  if [ ! -d "$WEBROOT" ]; then
    err "webroot 目录不存在：$WEBROOT"
    exit 1
  fi
  info "使用 webroot 模式申请证书..."
  ~/.acme.sh/acme.sh --issue -d "$DOMAIN" -w "$WEBROOT" --keylength ec-256 || true
  if [ -d "$HOME/.acme.sh/${DOMAIN}_ecc" ]; then
    CERT_DIR="$HOME/.acme.sh/${DOMAIN}_ecc"
  else
    CERT_DIR="$HOME/.acme.sh/$DOMAIN"
  fi
  mkdir -p /etc/ssl/xray
  ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray 2>/dev/null || true"
}

issue_cert_standalone(){
  info "使用 standalone 模式申请证书..."
  if [ -n "$STOP_SERVICE_CMD" ]; then
    systemctl stop "$STOP_SERVICE_CMD" || true
  fi
  ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 || true
  if [ -d "$HOME/.acme.sh/${DOMAIN}_ecc" ]; then
    CERT_DIR="$HOME/.acme.sh/${DOMAIN}_ecc"
  else
    CERT_DIR="$HOME/.acme.sh/$DOMAIN"
  fi
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
  info "生成自签名证书..."
  mkdir -p /etc/ssl/xray
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout /etc/ssl/xray/xray.key -out /etc/ssl/xray/xray.crt \
    -subj "/CN=${DOMAIN:-$PUB_IP}"
}

# issue cert
case $CHOICE in
  1) issue_cert_cloudflare ;;
  2) issue_cert_webroot ;;
  3) issue_cert_standalone ;;
  4) create_self_signed ;;
  5) warn "无 TLS 模式，跳过证书生成" ;;
esac

# verify cert
if [ "$CHOICE" -ne 5 ] && [ ! -f /etc/ssl/xray/xray.crt ]; then
  err "证书未生成"; exit 1
fi

# install Xray
info "安装 Xray-core..."
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install >/dev/null 2>&1 || true
ok "Xray 安装完成"

# generate Xray config
XRAY_DIR="/etc/xray"
mkdir -p "$XRAY_DIR"
UUID="$(cat /proc/sys/kernel/random/uuid)"
XRAY_PORT=$([ "$CHOICE" -eq 5 ] && echo 12345 || echo 443)
TLS_ENABLED=$([ "$CHOICE" -eq 5 ] && echo false || echo true)
WS_PATH="/websocket"

info "生成 Xray 配置..."
cat > "$XRAY_DIR/config.json" <<JSON
{
  "log": {"loglevel":"warning"},
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{"id":"$UUID","flow":""}],
        "decryption":"none"
      },
      "streamSettings": {
        "network":"ws",
        "wsSettings":{"path":"$WS_PATH","headers":{"Host":"${DOMAIN:-$PUB_IP}"}}$([ "$TLS_ENABLED" = true ] && cat <<'TLSBLOCK'
,
        "security":"tls",
        "tlsSettings":{
          "certificates":[{"certificateFile":"/etc/ssl/xray/xray.crt","keyFile":"/etc/ssl/xray/xray.key"}]
        }
TLSBLOCK
)
      }
    }
  ],
  "outbounds":[{"protocol":"freedom","settings":{}}]
}
JSON

chmod 600 "$XRAY_DIR/config.json"

# systemd start
info "启用并启动 xray..."
systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 2
if systemctl is-active --quiet xray; then ok "xray 已启动"; else err "xray 未启动"; exit 1; fi

# generate Clash config
CLASH_DIR="/etc/clash"
mkdir -p "$CLASH_DIR"

WS_PATH_ESCAPED=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote('$WS_PATH', safe=''))
PY)

SERVER_HOST=$([ "$TLS_ENABLED" = true ] && echo "$DOMAIN" || echo "$PUB_IP")

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
        Host: ${DOMAIN:-$SERVER_HOST}

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

# expose HTTP 9090
info "启动本地 HTTP 服务 (9090) 暴露 Clash 配置..."
if command -v lsof >/dev/null 2>&1; then
  OLDPID=$(lsof -t -i:9090 || true)
  [ -n "$OLDPID" ] && kill -9 $OLDPID || true
fi
nohup python3 -m http.server 9090 --directory "$CLASH_DIR" >/dev/null 2>&1 &

ok "完成！"
echo "Xray 配置: /etc/xray/config.json"
echo "Clash 配置: /etc/clash/config.yaml"
echo "Clash 订阅: http://$PUB_IP:9090/config.yaml"
echo "UUID: $UUID"
echo "ws path: $WS_PATH"
echo "端口: $XRAY_PORT"
