#!/bin/bash
set -e

# =============================
# Xray 一键安装脚本 (Debian 12)
# =============================

DOMAIN="你的域名"   # ← 这里换成你解析到服务器IP的域名
PORT=443
UUID=$(cat /proc/sys/kernel/random/uuid)
XRAY_DIR="/etc/xray"
CLASH_DIR="/etc/clash"

echo "[+] 更新系统..."
apt update -y && apt upgrade -y
apt install -y curl wget unzip socat net-tools

echo "[+] 安装 acme.sh 申请证书..."
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256
mkdir -p /etc/ssl/xray
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
  --ecc \
  --key-file       /etc/ssl/xray/xray.key \
  --fullchain-file /etc/ssl/xray/xray.crt

echo "[+] 安装 Xray..."
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

mkdir -p $XRAY_DIR

cat > $XRAY_DIR/config.json <<EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "level": 0 }]
    },
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "tlsSettings": {
        "certificates": [{
          "certificateFile": "/etc/ssl/xray/xray.crt",
          "keyFile": "/etc/ssl/xray/xray.key"
        }]
      },
      "wsSettings": { "path": "/websocket" }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

systemctl enable xray
systemctl restart xray

echo "[+] 生成 Clash 配置..."
mkdir -p $CLASH_DIR
cat > $CLASH_DIR/config.yaml <<EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: info

proxies:
  - name: "MyServer"
    type: vless
    server: $DOMAIN
    port: $PORT
    uuid: $UUID
    network: ws
    tls: true
    udp: true
    ws-opts:
      path: /websocket

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - MyServer

rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF

echo "[+] 提供订阅链接..."
kill -9 $(lsof -t -i:9090) 2>/dev/null || true
nohup python3 -m http.server 9090 --directory $CLASH_DIR >/dev/null 2>&1 &

IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)

echo "===================================="
echo "✅ Xray 安装完成！"
echo "服务器节点信息："
echo "协议: VLESS"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "UUID: $UUID"
echo "传输: WS"
echo "路径: /websocket"
echo "TLS : 启用"
echo
echo "Clash 客户端订阅地址："
echo "http://$IP:9090/config.yaml"
echo "===================================="
