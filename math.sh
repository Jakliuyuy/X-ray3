#!/bin/bash

# =========================================================
#  Math Uploader 托管平台：HTTP 纯净版 (v3.5)
#  域名：math.liuyuy.xyz -> 端口：7878
#  特性：独立Nginx配置、自动清理旧配置、菜单循环、MathJax支持
# =========================================================

# --- 基础配置 ---
DOMAIN="math.liuyuy.xyz"
WEB_PORT="7878"
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

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 权限运行！${PLAIN}" && exit 1

# --- 0. 自动安装命令 (修复无法调出菜单) ---
install_self() {
    CURRENT_PATH=$(readlink -f "$0")
    if [ "$CURRENT_PATH" != "$INSTALL_PATH" ]; then
        cp "$CURRENT_PATH" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        echo -e "${GREEN}✅ 系统命令 '$TOOL_NAME' 已就绪，下次可直接输入命令调出。${PLAIN}"
    fi
}

# --- 1. 更新 Nginx 配置 (独立文件模式) ---
update_nginx_config() {
    MODE=$1 
    AUTH_OPTS=""
    if [ "$MODE" == "on" ] && [ -f "$HTPASSWD_FILE" ]; then
        AUTH_OPTS="auth_basic \"Restricted Area\"; auth_basic_user_file $HTPASSWD_FILE;"
    fi

    echo -e "${YELLOW}>>> 正在清理冲突并生成 Nginx 配置...${PLAIN}"
    
    # 清理旧的 sites-available 软链接和文件
    rm -f "/etc/nginx/sites-enabled/html_uploader.conf"
    rm -f "/etc/nginx/sites-available/html_uploader.conf"

    # 生成独立的 conf 文件
    cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size 50M;
    $AUTH_OPTS

    # 转发到本地 Node 后端 (7878)
    location / {
        proxy_pass http://127.0.0.1:${WEB_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # 静态资源托管优化 (支持跨域加载 MathJax)
    location /u/ {
        alias $APP_DIR/uploads/;
        index index.html;
        add_header Access-Control-Allow-Origin *;
        expires 1h;
    }
}
EOF

    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}✅ Nginx 配置已成功应用！${PLAIN}"
    else
        echo -e "${RED}❌ Nginx 配置语法错误，请检查。${PLAIN}"
    fi
}

# --- 2. 核心环境安装 ---
do_install() {
    install_self
    echo -e "${YELLOW}>>> 正在安装运行环境...${PLAIN}"
    
    if command -v apt >/dev/null 2>&1; then
        apt update -y && apt install -y nginx nodejs npm curl git apache2-utils
    else
        yum install -y epel-release nginx nodejs git httpd-tools
    fi

    if ! command -v pm2 >/dev/null 2>&1; then npm install -g pm2; fi

    mkdir -p $APP_DIR/{uploads,public}
    cd $APP_DIR

    # 写入后端 server.js
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
        if (!file.originalname.toLowerCase().endsWith(".html")) return cb(new Error("仅限HTML"));
        cb(null, true);
    }
});
app.use(express.static("public"));
app.post("/upload", upload.single("html"), (req, res) => {
    if (!req.file) return res.status(400).json({ error: "无效文件" });
    const id = crypto.randomBytes(4).toString("hex");
    const dir = path.join(__dirname, "uploads", id);
    try {
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, "index.html"), req.file.buffer);
        res.json({ id, url: "/u/" + id + "/" });
    } catch (e) { res.status(500).json({ error: "存储失败" }); }
});
app.post("/delete", (req, res) => {
    const { id } = req.body;
    const dir = path.join(__dirname, "uploads", id);
    if (fs.existsSync(dir)) {
        fs.rmSync(dir, { recursive: true, force: true });
        res.json({ success: true });
    } else { res.status(404).json({ error: "未找到" }); }
});
app.listen(7878, "127.0.0.1", () => console.log("Internal Server on 7878"));
EOF

    # 写入前端 (使用 MathJax 渲染公式)
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8"><title>数学课件平台</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 min-h-screen p-6">
    <div class="max-w-xl mx-auto bg-white p-8 rounded-2xl shadow-sm border">
        <h1 class="text-2xl font-bold text-center mb-6">课件管理控制台</h1>
        <div class="border-2 border-dashed border-gray-200 rounded-xl p-10 text-center hover:border-blue-400 transition cursor-pointer" onclick="document.getElementById('file').click()">
            <input type="file" id="file" class="hidden" accept=".html">
            <span id="fname" class="text-gray-400">点击此处选择 HTML 课件</span>
        </div>
        <button onclick="upload()" class="w-full mt-6 bg-blue-600 text-white py-3 rounded-xl font-bold hover:bg-blue-700 transition">立即上传</button>
        <div id="list" class="mt-8 space-y-3"></div>
    </div>
    <script>
        const fileInput = document.getElementById('file');
        fileInput.onchange = () => { if(fileInput.files[0]) document.getElementById('fname').innerText = fileInput.files[0].name; };
        async function upload() {
            const f = fileInput.files[0]; if(!f) return alert("请选文件");
            const fd = new FormData(); fd.append("html", f);
            const res = await fetch("/upload", { method: "POST", body: fd });
            const d = await res.json();
            if(d.id) {
                let data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
                data.unshift({id:d.id, name:f.name, date:new Date().toLocaleString()});
                localStorage.setItem('my_htmls', JSON.stringify(data));
                render(); alert("发布成功");
            }
        }
        function render() {
            const list = document.getElementById('list');
            const data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
            list.innerHTML = data.map(i => `
                <div class="flex justify-between items-center p-4 bg-gray-50 rounded-lg border">
                    <div class="truncate mr-4"><p class="font-medium truncate">${i.name}</p><p class="text-xs text-gray-400">${i.date}</p></div>
                    <div class="flex space-x-2">
                        <a href="/u/${i.id}/" target="_blank" class="text-blue-600 text-sm font-bold">查看</a>
                        <button onclick="del('${i.id}')" class="text-red-500 text-sm">删除</button>
                    </div>
                </div>`).join('');
        }
        async function del(id) {
            if(!confirm("确定删除？")) return;
            await fetch("/delete", { method:"POST", headers:{'Content-Type':'application/json'}, body:JSON.stringify({id}) });
            let data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
            localStorage.setItem('my_htmls', JSON.stringify(data.filter(x => x.id !== id)));
            render();
        }
        render();
    </script>
</body>
</html>
EOF

    # 启动应用
    pm2 delete $PM2_NAME 2>/dev/null || true
    pm2 start server.js --name $PM2_NAME
    pm2 save
    
    update_nginx_config "off"
    echo -e "${GREEN}>>> 安装成功！访问地址: http://$DOMAIN${PLAIN}"
}

# --- 3. 菜单系统 (循环修复) ---
show_menu() {
    install_self
    while true; do
        echo -e "\n${YELLOW}====================================${PLAIN}"
        echo -e "   数学平台管理菜单 (HTTP版)"
        echo -e "${YELLOW}====================================${PLAIN}"
        echo -e " 1. 重启服务 (PM2 + Nginx)"
        echo -e " 2. 开启/修改 访问密码"
        echo -e " 3. 关闭 访问密码 (公开模式)"
        echo -e " 4. 查看运行日志"
        echo -e " 5. 卸载项目"
        echo -e " 0. 退出程序"
        echo -e "------------------------------------"
        read -p "请输入选项: " num

        case "$num" in
            1) pm2 restart $PM2_NAME; systemctl reload nginx; echo "已重启"; ;;
            2) read -p "用户名: " user; read -s -p "密码: " pass; echo ""; htpasswd -bc "$HTPASSWD_FILE" "$user" "$pass"; update_nginx_config "on"; ;;
            3) update_nginx_config "off"; echo "已切换为公开模式"; ;;
            4) pm2 logs $PM2_NAME --lines 30; ;;
            5) read -p "确定卸载? (y/n): " cf; if [ "$cf" == "y" ]; then pm2 delete $PM2_NAME; rm -rf $APP_DIR $NGINX_CONF $INSTALL_PATH; systemctl reload nginx; exit 0; fi; ;;
            0) exit 0 ;;
            *) echo "无效选择" ;;
        esac
        echo -e "\n按回车键返回主菜单..."
        read
    done
}

# --- 程序入口 ---
if [ ! -d "$APP_DIR" ]; then
    do_install
    show_menu
else
    show_menu
fi
