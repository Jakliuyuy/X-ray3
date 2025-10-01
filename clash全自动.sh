#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "❌ 错误：请传入订阅地址，例如："
  echo 'bash <(curl -Ls https://raw.githubusercontent.com/liu-auto/clash-debian12/main/clash-sub.sh) "http://example.com/sub.yaml"'
  exit 1
fi

SUB_URL="$1"

echo "[+] 更新系统..."
apt update -y && apt upgrade -y
apt install -y wget curl tar python3 lsof

CLASH_DIR="/etc/clash"
CLASH_BIN="/usr/local/bin/clash"
CLASH_URL="https://github.com/Dreamacro/clash/releases/latest/download/clash-linux-amd64-v3"
CLASH_SERVICE="/etc/systemd/system/clash.service"

# 创建目录
mkdir -p $CLASH_DIR
cd $CLASH_DIR

# 下载 Clash 内核
if [ ! -f "$CLASH_BIN" ]; then
    echo "[+] 下载 Clash 核心..."
    wget -O $CLASH_BIN $CLASH_URL
    chmod +x $CLASH_BIN
fi

# 拉取订阅配置
echo "[+] 下载订阅配置..."
curl -L -o $CLASH_DIR/config.yaml "$SUB_URL"

# 写入 systemd 服务
cat > $CLASH_SERVICE <<EOT
[Unit]
Description=Clash Proxy
After=network.target
[Service]
ExecStart=$CLASH_BIN -d $CLASH_DIR
Restart=always
RestartSec=5
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
EOT

# 启动并设置开机自启
systemctl daemon-reexec
systemctl enable clash
systemctl restart clash

# 启动 http server 暴露订阅
kill -9 $(lsof -t -i:9090) 2>/dev/null || true
cd $CLASH_DIR
nohup python3 -m http.server 9090 >/dev/null 2>&1 &

# 输出订阅地址
IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)
echo "===================================="
echo "Clash 安装完成 ✅"
echo "订阅文件已使用: $SUB_URL"
echo "客户端订阅链接: http://$IP:9090/config.yaml"
echo "===================================="
