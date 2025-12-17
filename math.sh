cat > /usr/local/bin/webtool << 'EOF'
#!/bin/bash
# =========================================================
#  Math Uploader 托管平台：HTTP 纯净版 (v3.5)
#  域名：math.liuyuy.xyz -> 端口：7878
# =========================================================

DOMAIN="math.liuyuy.xyz"
WEB_PORT="7878"
APP_DIR="/var/www/html-uploader"
PM2_NAME="html-uploader"
NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"
HTPASSWD_FILE="/etc/nginx/.html_uploader_htpasswd"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 运行！${PLAIN}" && exit 1

update_nginx_config() {
    MODE=$1
    AUTH_OPTS=""
    if [ "$MODE" == "on" ] && [ -f "$HTPASSWD_FILE" ]; then
        AUTH_OPTS="auth_basic \"Restricted Area\"; auth_basic_user_file $HTPASSWD_FILE;"
    fi
    rm -f "/etc/nginx/sites-enabled/html_uploader.conf"
    rm -f "/etc/nginx/sites-available/html_uploader.conf"
    cat > "$NGINX_CONF" << EON
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 50M;
    $AUTH_OPTS
    location / {
        proxy_pass http://127.0.0.1:${WEB_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /u/ {
        alias $APP_DIR/uploads/;
        index index.html;
        add_header Access-Control-Allow-Origin *;
    }
}
EON
    nginx -t && systemctl reload nginx
}

while true; do
    clear
    echo -e "${GREEN}=== 数学平台管理 ($DOMAIN) ===${PLAIN}"
    echo -e " 1. 修复并启动服务 (安装依赖+重启)"
    echo -e " 2. 设置/修改 访问密码"
    echo -e " 3. 关闭 访问密码"
    echo -e " 4. 查看日志 (排查错误)"
    echo -e " 5. 卸载项目"
    echo -e " 0. 退出"
    echo -e "------------------------------------"
    read -p "请输入选项: " num

    case "$num" in
        1)
            echo "正在修复依赖..."
            cd $APP_DIR
            npm install express multer
            pm2 delete $PM2_NAME 2>/dev/null
            pm2 start server.js --name $PM2_NAME
            update_nginx_config "off"
            echo -e "${GREEN}修复完成！${PLAIN}"
            ;;
        2) read -p "用户名: " user; read -s -p "密码: " pass; echo ""; htpasswd -bc "$HTPASSWD_FILE" "$user" "$pass"; update_nginx_config "on"; ;;
        3) update_nginx_config "off"; echo "已切换为公开模式"; ;;
        4) pm2 logs $PM2_NAME --lines 30; ;;
        5) read -p "确定卸载? (y/n): " cf; if [ "$cf" == "y" ]; then pm2 delete $PM2_NAME; rm -rf $APP_DIR $NGINX_CONF /usr/local/bin/webtool; systemctl reload nginx; exit 0; fi; ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
    read -p "按回车键继续..."
done
EOF

# 赋予执行权限
chmod +x /usr/local/bin/webtool

# 立即运行
webtool
