#!/bin/bash

# ==========================================
#   HTML 托管平台：生产级最终版 (v2.0)
#   端口：7878 | 域名：math.liuyuy.xyz
#   修复：前端补全、Swap去重、JSON解析、配置回滚
# ==========================================

APP_DIR="/var/www/html-uploader"
PM2_NAME="html-uploader"
SHORTCUT="/usr/local/bin/webtool"
HTPASSWD_FILE="/etc/nginx/.html_uploader_htpasswd"

# 用户配置区
MY_DOMAIN="math.liuyuy.xyz"
MY_PORT="7878"

# Nginx 路径
NGINX_AVAIL="/etc/nginx/sites-available/html_uploader.conf"
NGINX_ENABL="/etc/nginx/sites-enabled/html_uploader.conf"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 Root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 运行此脚本！${PLAIN}" && exit 1

# --- 1. 核心：更新 Nginx 配置 (带备份与回滚) ---
update_nginx_config() {
    MODE=$1
    AUTH_LINE=""
    # 只有当模式为 on 且密码文件存在时才开启
    if [ "$MODE" == "on" ] && [ -f "$HTPASSWD_FILE" ]; then
        AUTH_LINE="auth_basic \"Restricted Area\"; auth_basic_user_file $HTPASSWD_FILE;"
    fi

    # 1. 备份旧配置
    if [ -f "$NGINX_AVAIL" ]; then
        cp "$NGINX_AVAIL" "$NGINX_AVAIL.bak"
    fi

    # 2. 写入新配置
    # 注意：server_name 包含 _ 以允许 IP 访问
    cat > "$NGINX_AVAIL" << EOF
server {
    listen $MY_PORT;
    server_name $MY_DOMAIN _;

    client_max_body_size 10M; # 允许稍微大一点的 HTML
    $AUTH_LINE

    # 接口反代
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # 静态文件托管
    location /u/ { 
        alias $APP_DIR/uploads/; 
        index index.html; 
        # 允许跨域 (关键：解决 MathJax CDN 加载问题)
        add_header Access-Control-Allow-Origin *;
        expires 1h; 
    }
}
EOF

    # 3. 建立软链接
    ln -sf "$NGINX_AVAIL" "$NGINX_ENABL"

    # 4. 防火墙放行 (针对 7878 端口)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $MY_PORT/tcp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --add-port=$MY_PORT/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi

    # 5. 测试并重载
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}Nginx 配置更新成功！${PLAIN}"
    else
        echo -e "${RED}Nginx 配置错误！正在回滚...${PLAIN}"
        [ -f "$NGINX_AVAIL.bak" ] && mv "$NGINX_AVAIL.bak" "$NGINX_AVAIL"
        ln -sf "$NGINX_AVAIL" "$NGINX_ENABL"
        nginx -t && systemctl reload nginx
        echo -e "${YELLOW}已回滚到上一次正确的配置。${PLAIN}"
    fi
}

# --- 2. 核心：安装逻辑 ---
do_install() {
    echo -e "${YELLOW}>>> 开始安装依赖...${PLAIN}"

    # 系统判断与依赖安装
    if command -v apt >/dev/null 2>&1; then
        apt update -y
        apt install -y nginx nodejs npm curl git apache2-utils
    else
        # CentOS/RHEL 处理
        yum install -y epel-release
        curl -sL https://rpm.nodesource.com/setup_18.x | bash -
        yum install -y nginx nodejs git httpd-tools
    fi

    # 必装 PM2 (之前缺失点修复)
    if ! command -v pm2 >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装 PM2...${PLAIN}"
        npm install -g pm2
    fi

    # Swap 内存优化 (去重修复)
    if ! swapon --show | grep -q swapfile; then
        echo -e "${YELLOW}创建 1G Swap...${PLAIN}"
        fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        # 防止重复写入 fstab
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
    fi

    # 准备目录
    mkdir -p $APP_DIR/{uploads,public}
    cd $APP_DIR

    # 初始化 Node 项目
    if [ ! -f "package.json" ]; then
        npm init -y > /dev/null
        npm install express multer > /dev/null
    fi

    # --- 写入后端 (server.js) ---
    echo -e "${YELLOW}>>> 写入后端代码...${PLAIN}"
    cat > server.js << 'EOF'
const express = require("express");
const multer = require("multer");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const app = express();

// 【修复】必须解析 JSON，否则前端无法提交删除请求
app.use(express.json());

// 【修复】Multer 使用内存存储，配合 Buffer 使用
const upload = multer({ 
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024 }, // 5MB 限制
    fileFilter(req, file, cb) {
        if (!file.originalname.toLowerCase().endsWith(".html")) {
            return cb(new Error("仅允许上传 .html 文件"));
        }
        cb(null, true);
    }
});

app.use(express.static("public"));

// 上传接口
app.post("/upload", upload.single("html"), (req, res) => {
    if (!req.file) return res.status(400).json({ error: "文件无效" });
    
    const id = crypto.randomBytes(4).toString("hex");
    const dir = path.join(__dirname, "uploads", id);
    
    try {
        fs.mkdirSync(dir, { recursive: true });
        // 写入文件
        fs.writeFileSync(path.join(dir, "index.html"), req.file.buffer);
        res.json({ id: id, url: "/u/" + id + "/" });
    } catch (e) {
        res.status(500).json({ error: "存储失败" });
    }
});

// 删除接口
app.post("/delete", (req, res) => {
    const { id } = req.body;
    // 安全校验：只允许 8 位 hex 字符，防止路径遍历攻击
    if (!/^[a-f0-9]{8}$/.test(id)) return res.status(400).json({ error: "ID 格式非法" });

    const dir = path.join(__dirname, "uploads", id);
    if (fs.existsSync(dir)) {
        fs.rmSync(dir, { recursive: true, force: true });
        res.json({ success: true });
    } else {
        res.status(404).json({ error: "文件不存在" });
    }
});

app.listen(3000, "127.0.0.1", () => console.log("Backend Running on 3000"));
EOF

    # --- 写入前端 (index.html) ---
    # 【修复】补全之前省略的前端代码
    echo -e "${YELLOW}>>> 写入前端代码...${PLAIN}"
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>数学平台管理</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
</head>
<body class="bg-gray-50 min-h-screen p-4 font-sans">
    <div class="max-w-2xl mx-auto space-y-6">
        <div class="bg-white p-6 rounded-xl shadow-sm border border-gray-200">
            <h1 class="text-xl font-bold text-gray-800 mb-4 text-center">WebUploader 教学资源托管</h1>
            <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-blue-500 transition cursor-pointer" onclick="document.getElementById('file').click()">
                <input type="file" id="file" class="hidden" accept=".html">
                <p class="text-gray-500" id="fname">点击或拖拽上传 HTML 课件</p>
            </div>
            <button onclick="upload()" class="w-full mt-4 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700">上传并发布</button>
        </div>

        <div class="bg-white p-6 rounded-xl shadow-sm border border-gray-200">
            <h2 class="text-lg font-bold text-gray-700 mb-4">我的课件列表</h2>
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
                if(d.id) {
                    save(d.id, f.name);
                    render();
                    alert("发布成功！");
                } else { alert("上传失败"); }
            } catch(e) { alert("网络错误"); }
        }

        async function del(id) {
            if(!confirm("确定删除？")) return;
            const res = await fetch("/delete", {
                method: "POST",
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({id})
            });
            if(res.ok) {
                let data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
                data = data.filter(i => i.id !== id);
                localStorage.setItem('my_htmls', JSON.stringify(data));
                render();
            } else { alert("删除失败"); }
        }

        function save(id, name) {
            let data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
            data.unshift({id, name, date: new Date().toLocaleTimeString()});
            localStorage.setItem('my_htmls', JSON.stringify(data));
        }

        function render() {
            const list = document.getElementById('list');
            const data = JSON.parse(localStorage.getItem('my_htmls')||'[]');
            if(!data.length) return list.innerHTML = '<p class="text-gray-400 text-center text-sm">暂无记录</p>';
            
            // 注意：这里手动构建 URL，端口取当前访问端口
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
                </div>
            `).join('');
        }
    </script>
</body>
</html>
EOF

    # --- 启动服务 ---
    echo -e "${YELLOW}>>> 启动服务...${PLAIN}"
    # 初始化 Nginx 配置 (默认关闭密码)
    update_nginx_config "off"

    # PM2 启动 (内存限制 + 自启)
    pm2 delete $PM2_NAME 2>/dev/null || true
    pm2 start server.js --name $PM2_NAME --node-args="--max-old-space-size=128"
    pm2 save
    pm2 startup | grep -v "\[PM2\]" | bash >/dev/null 2>&1 || true

    # 建立快捷命令 (使用绝对路径修复 dangling symlink 问题)
    SCRIPT_PATH=$(realpath "$0")
    rm -f "$SHORTCUT"
    ln -s "$SCRIPT_PATH" "$SHORTCUT"
    chmod +x "$SHORTCUT"

    echo -e "${GREEN}=======================================${PLAIN}"
    echo -e "${GREEN} ✅ 安装成功！${PLAIN}"
    echo -e " 访问地址: http://$MY_DOMAIN:$MY_PORT"
    echo -e " 管理命令: webtool"
    echo -e "${GREEN}=======================================${PLAIN}"
}

# --- 菜单系统 ---
show_menu() {
    clear
    echo -e "${GREEN}=== 数学平台管理 ($MY_DOMAIN:$MY_PORT) ===${PLAIN}"
    echo -e " 1. 重启服务 (应用所有更改)"
    echo -e " 2. 设置/修改 访问密码"
    echo -e " 3. 关闭 访问密码 (公开模式)"
    echo -e " 4. 查看运行日志"
    echo -e " 5. 卸载整个项目"
    echo -e " 0. 退出"
    echo -e "----------------------------------------"
    read -p "请输入选项 [0-5]: " num

    case "$num" in
        1) 
            pm2 restart $PM2_NAME
            systemctl reload nginx
            echo -e "${GREEN}服务已重启${PLAIN}"
            read -p "按回车继续..." 
            ;;
        2) 
            echo -e "${YELLOW}设置访问账号密码...${PLAIN}"
            read -p "用户名: " user
            read -s -p "密码: " pass
            echo ""
            htpasswd -bc "$HTPASSWD_FILE" "$user" "$pass"
            update_nginx_config "on"
            read -p "按回车继续..." 
            ;;
        3) 
            update_nginx_config "off"
            echo -e "${GREEN}已关闭密码验证${PLAIN}"
            read -p "按回车继续..." 
            ;;
        4) 
            pm2 logs $PM2_NAME --lines 20
            ;;
        5) 
            read -p "确定要彻底删除吗？(y/n): " confirm
            if [ "$confirm" == "y" ]; then
                pm2 delete $PM2_NAME
                rm -rf $APP_DIR
                rm -f "$NGINX_AVAIL" "$NGINX_ENABL" "$SHORTCUT"
                systemctl reload nginx
                echo -e "${GREEN}卸载完成${PLAIN}"
                exit 0
            fi
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}"; sleep 1 ;;
    esac
}

# --- 入口逻辑 ---
if [ ! -d "$APP_DIR" ]; then
    do_install
else
    # 每次运行 webtool 自动修复一次软链接，防止移动脚本后失效
    SCRIPT_PATH=$(realpath "$0")
    if [ "$(readlink -f $SHORTCUT)" != "$SCRIPT_PATH" ]; then
        rm -f "$SHORTCUT"
        ln -s "$SCRIPT_PATH" "$SHORTCUT"
        chmod +x "$SHORTCUT"
    fi
    show_menu
fi
