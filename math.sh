#!/bin/bash

# =========================================================
#  Math Uploader 托管平台：自定义端口版 (v3.1)
#  域名：math.liuyuy.xyz | 端口：7878 (HTTPS)
#  特性：独立Nginx配置、自动SSL、菜单修复、防火墙放行
# =========================================================

# --- 配置区 ---
DOMAIN="math.liuyuy.xyz"
WEB_PORT="7878"  # <--- 已修改为 7878
APP_DIR="/var/www/html-uploader"
PM2_NAME="html-uploader"
TOOL_NAME="webtool"
INSTALL_PATH="/usr/local/bin/$TOOL_NAME"
HTPASSWD_FILE="/etc/nginx/.html_uploader_htpasswd"
NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 Root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 运行此脚本！${PLAIN}" && exit 1

# --- 0. 核心：自我安装与菜单修复 ---
install_self() {
    CURRENT_PATH=$(readlink -f "$0")
    if [ "$CURRENT_PATH" != "$INSTALL_PATH" ]; then
        echo -e "${YELLOW}正在更新系统命令 '$TOOL_NAME'...${PLAIN}"
        cp "$CURRENT_PATH" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        echo -e "${GREEN}✅ 命令已安装！以后输入 '$TOOL_NAME' 即可调出菜单。${PLAIN}"
        sleep 1
    fi
}

# --- 1. 核心：生成 Nginx 配置 (7878 SSL) ---
update_nginx_config() {
    MODE=$1 
    AUTH_OPTS=""

    # 密码保护逻辑
    if [ "$MODE" == "on" ] && [ -f "$HTPASSWD_FILE" ]; then
        AUTH_OPTS="auth_basic \"Restricted Area\"; auth_basic_user_file $HTPASSWD_FILE;"
    fi

    # 证书路径检查
    CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    KEY_FILE="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

    if [ ! -f "$CERT_FILE" ]; then
        echo -e "${RED}❌ 未检测到 SSL 证书！${PLAIN}"
        echo "请确保 /etc/letsencrypt/live/${DOMAIN}/ 目录下有证书文件。"
        read -p "按回车键强制继续 (Nginx 可能会启动失败)..."
    fi

    echo -e "${YELLOW}正在生成 Nginx 配置文件 (端口 $WEB_PORT)...${PLAIN}"

    # 写入配置 (独立文件，监听 7878)
    cat > "$NGINX_CONF" << EOF
server {
    listen $WEB_PORT ssl;  # <--- 监听 7878 SSL
    server_name ${DOMAIN};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    client_max_body_size 50M; 

    $AUTH_OPTS

    # Node 后端接口反代
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # 静态文件托管
    location /u/ {
        alias $APP_DIR/uploads/;
        index index.html;
        add_header Access-Control-Allow-Origin *;
        expires 1h;
    }
}

# (可选) HTTP 80 端口自动跳转到 HTTPS 7878
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host:$WEB_PORT\$request_uri;
}
EOF

    echo -e "${GREEN}配置已写入: $NGINX_CONF${PLAIN}"

    # 放行防火墙端口 (关键)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $WEB_PORT/tcp >/dev/null 2>&1
        echo -e "已通过 UFW 放行端口 $WEB_PORT"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --add-port=$WEB_PORT/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "已通过 FirewallD 放行端口 $WEB_PORT"
    fi

    # 测试并重载
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}✅ Nginx 重载成功！${PLAIN}"
    else
        echo -e "${RED}❌ Nginx 配置测试失败！${PLAIN}"
        rm -f "$NGINX_CONF"
        echo "已自动删除错误配置。"
    fi
}

# --- 2. 核心：环境安装与部署 ---
do_install() {
    install_self 
    echo -e "${YELLOW}>>> 开始安装依赖...${PLAIN}"
    
    # 依赖安装
    if command -v apt >/dev/null 2>&1; then
        apt update -y
        apt install -y nginx nodejs npm curl git apache2-utils
    else
        yum install -y epel-release nginx nodejs git httpd-tools
    fi

    if ! command -v pm2 >/dev/null 2>&1; then npm install -g pm2; fi

    mkdir -p $APP_DIR/{uploads,public}
    cd $APP_DIR

    if [ ! -f "package.json" ]; then
        npm init -y > /dev/null
        npm install express multer > /dev/null
    fi

    # 写入 server.js (后端端口保持 3000 内部运行)
    cat > server.js << 'EOF'
const express = require("express");
const multer = require("multer");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const app = express();

app.use(express.json());

const upload = multer({ 
    storage: multer.memoryStorage(),
    limits: { fileSize: 50 * 1024 * 1024 },
    fileFilter(req, file, cb) {
        if (!file.originalname.toLowerCase().endsWith(".html")) {
            return cb(new Error("仅允许上传 .html 文件"));
        }
        cb(null, true);
    }
});

app.use(express.static("public"));

app.post("/upload", upload.single("html"), (req, res) => {
    if (!req.file) return res.status(400).json({ error: "文件无效" });
    const id = crypto.randomBytes(4).toString("hex");
    const dir = path.join(__dirname, "uploads", id);
    try {
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, "index.html"), req.file.buffer);
        res.json({ id: id, url: "/u/" + id + "/" });
    } catch (e) { res.status(500).json({ error: "存储失败" }); }
});

app.post("/delete", (req, res) => {
    const { id } = req.body;
    if (!/^[a-f0-9]{8}$/.test(id)) return res.status(400).json({ error: "ID非法" });
    const dir = path.join(__dirname, "uploads", id);
    if (fs.existsSync(dir)) {
        fs.rmSync(dir, { recursive: true, force: true });
        res.json({ success: true });
    } else { res.status(404).json({ error: "不存在" }); }
});

app.listen(3000, "127.0.0.1", () => console.log("Running on 3000"));
EOF

    # 写入 index.html
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>数学课件托管</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 min-h-screen p-4 font-sans">
    <div class="max-w-2xl mx-auto space-y-6">
        <div class="bg-white p-6 rounded-xl shadow-sm border border-gray-200">
            <h1 class="text-xl font-bold text-gray-800 mb-4 text-center">Math Uploader</h1>
            <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-blue-500 transition cursor-pointer" onclick="document.getElementById('file').click()">
                <input type="file" id="file" class="hidden" accept=".html">
                <p class="text-gray-500" id="fname">点击上传 HTML 课件</p>
            </div>
            <button onclick="upload()" class="w-full mt-4 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700">上传发布</button>
        </div>
        <div class="bg-white p-6 rounded-xl shadow-sm border border-gray-200">
            <h2 class="text-lg font-bold text-gray-700 mb-4">课件列表</h2>
            <div id="list" class="space-y-2"></div>
        </div>
    </div>
    <script>
        const fileInput = document.getElementById('file');
        fileInput.onchange = () => { if(fileInput.files[0]) document.getElementById('fname').innerText = fileInput.files[0].name; };
        render();

        async function upload() {
            const f = fileInput.files[0];
            if(!f) return alert("请选文件");
            const fd = new FormData();
            fd.append("html", f);
            try {
                const res = await fetch("/upload", { method: "POST", body: fd });
                const d = await res.json();
                if(d.id) { save(d.id, f.name); render(); alert("发布成功！"); } 
                else { alert("上传失败"); }
            } catch(e) { alert("网络错误"); }
        }

        async function del(id) {
            if(!confirm("确定删除？")) return;
            await fetch("/delete", { method: "POST", headers: {'Content-Type': 'application/json'}, body: JSON.stringify({id}) });
            let data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
            localStorage.setItem('my_htmls', JSON.stringify(data.filter(i => i.id !== id)));
            render();
        }

        function save(id, name) {
            let data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
            data.unshift({id, name, date: new Date().toLocaleTimeString()});
            localStorage.setItem('my_htmls', JSON.stringify(data));
        }

        function render() {
            const list = document.getElementById('list');
            const data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
            // 自动适配当前端口
            const port = window.location.port ? ":" + window.location.port : "";
            const origin = window.location.protocol + "//" + window.location.hostname + port;
            
            list.innerHTML = data.map(i => `
                <div class="flex justify-between items-center bg-gray-50 p-3 rounded border">
                    <div class="truncate w-1/2">
                        <div class="font-medium text-gray-700 truncate">${i.name}</div>
                        <div class="text-xs text-gray-400">${i.date}</div>
                    </div>
                    <div class="flex space-x-2 shrink-0">
                        <a href="${origin}/u/${i.id}/" target="_blank" class="text-xs bg-white border px-2 py-1 rounded text-blue-600">查看</a>
                        <button onclick="del('${i.id}')" class="text-xs bg-white border px-2 py-1 rounded text-red-600">删除</button>
                    </div>
                </div>`).join('');
        }
    </script>
</body>
</html>
EOF

    # 启动服务
    echo -e "${YELLOW}>>> 启动服务...${PLAIN}"
    pm2 delete $PM2_NAME 2>/dev/null || true
    pm2 start server.js --name $PM2_NAME
    pm2 save
    pm2 startup | grep -v "\[PM2\]" | bash >/dev/null 2>&1 || true

    update_nginx_config "off"

    echo -e "${GREEN}=======================================${PLAIN}"
    echo -e " 安装完成！"
    echo -e " 访问地址: https://$DOMAIN:$WEB_PORT"
    echo -e " 管理命令: $TOOL_NAME"
    echo -e "${GREEN}=======================================${PLAIN}"
}

# --- 菜单系统 ---
show_menu() {
    install_self
    while true; do
        echo -e "\n${GREEN}=== 数学平台管理 ($DOMAIN:$WEB_PORT) ===${PLAIN}"
        echo -e " 1. 重启服务"
        echo -e " 2. 设置/修改 访问密码"
        echo -e " 3. 关闭 访问密码 (公开)"
        echo -e " 4. 查看日志"
        echo -e " 5. 卸载项目"
        echo -e " 0. 退出"
        echo -e "----------------------------------------"
        read -p "请输入选项: " num

        case "$num" in
            1) 
                pm2 restart $PM2_NAME
                systemctl reload nginx
                echo -e "${GREEN}已重启${PLAIN}"
                ;;
            2) 
                read -p "用户名: " user
                read -s -p "密码: " pass
                echo ""
                htpasswd -bc "$HTPASSWD_FILE" "$user" "$pass"
                update_nginx_config "on"
                ;;
            3) 
                update_nginx_config "off"
                echo -e "${GREEN}已设为公开模式${PLAIN}"
                ;;
            4) 
                pm2 logs $PM2_NAME --lines 20
                ;;
            5) 
                read -p "确定卸载? (y/n): " cfm
                if [ "$cfm" == "y" ]; then
                    pm2 delete $PM2_NAME
                    rm -rf $APP_DIR
                    rm -f "$NGINX_CONF" "$INSTALL_PATH"
                    systemctl reload nginx
                    echo "已卸载。"
                    exit 0
                fi
                ;;
            0) exit 0 ;;
            *) echo "无效选项" ;;
        esac
        echo ""
        read -p "按回车返回菜单..."
    done
}

# --- 入口 ---
if [ ! -d "$APP_DIR" ]; then
    do_install
    show_menu
else
    show_menu
fi
