cat > /usr/local/bin/webtool << 'EOF'
#!/bin/bash
# =========================================================
#  MathHub 终极版 (v4.5) - 包含精美原生登录页
# =========================================================

DOMAIN="math.liuyuy.xyz"
APP_DIR="/var/www/html-uploader"
PM2_NAME="html-uploader"
NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"

[[ $EUID -ne 0 ]] && echo "请用 root 运行" && exit 1

write_files() {
    mkdir -p $APP_DIR/{uploads,public}
    
    # 1. 后端 server.js (包含简单的登录验证逻辑)
    cat > $APP_DIR/server.js << 'EON'
const express = require("express");
const multer = require("multer");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const app = express();
const LIST_PATH = path.join(__dirname, "uploads/list.json");

app.use(express.json());
app.use(express.static("public"));

// 简单的 Session 模拟 (密码保存在后端)
let AUTH_PASS = "123456"; // 默认密码

app.post("/api/login", (req, res) => {
    const { password } = req.body;
    if (password === AUTH_PASS) res.json({ success: true, token: "math-secret-token" });
    else res.status(401).json({ error: "密码错误" });
});

app.get("/api/list", (req, res) => {
    if (!fs.existsSync(LIST_PATH)) return res.json([]);
    res.json(JSON.parse(fs.readFileSync(LIST_PATH)));
});

const upload = multer({ storage: multer.memoryStorage() });
app.post("/upload", upload.single("html"), (req, res) => {
    const id = crypto.randomBytes(4).toString("hex");
    const dir = path.join(__dirname, "uploads", id);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "index.html"), req.file.buffer);
    
    let list = fs.existsSync(LIST_PATH) ? JSON.parse(fs.readFileSync(LIST_PATH)) : [];
    list.unshift({ id, name: req.file.originalname, date: new Date().toLocaleString('zh-CN') });
    fs.writeFileSync(LIST_PATH, JSON.stringify(list));
    res.json({ id });
});

app.post("/delete", (req, res) => {
    const { id } = req.body;
    const dir = path.join(__dirname, "uploads", id);
    if (fs.existsSync(dir)) fs.rmSync(dir, { recursive: true, force: true });
    let list = JSON.parse(fs.readFileSync(LIST_PATH)).filter(i => i.id !== id);
    fs.writeFileSync(LIST_PATH, JSON.stringify(list));
    res.json({ success: true });
});

app.listen(7878, "127.0.0.1");
EON

    # 2. 前端 index.html (包含登录 UI 和 管理 UI)
    cat > $APP_DIR/public/index.html << 'EON'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MathHub 教学管理系统</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
</head>
<body class="bg-slate-50 min-h-screen text-slate-800">
    <div id="login-overlay" class="fixed inset-0 z-[100] bg-slate-900 flex items-center justify-center p-4">
        <div class="bg-white w-full max-w-sm rounded-3xl shadow-2xl overflow-hidden animate-in fade-in zoom-in duration-300">
            <div class="bg-blue-600 p-8 text-white text-center">
                <div class="w-16 h-16 bg-white/20 rounded-2xl flex items-center justify-center mx-auto mb-4">
                    <i class="fas fa-lock text-2xl"></i>
                </div>
                <h2 class="text-2xl font-bold">身份验证</h2>
                <p class="text-blue-100 mt-1 text-sm">请输入密码以访问管理后台</p>
            </div>
            <div class="p-8">
                <input type="password" id="login-pass" class="w-full px-4 py-3 rounded-xl border border-slate-200 focus:ring-2 focus:ring-blue-500 outline-none transition-all mb-4" placeholder="访问密码">
                <button onclick="doLogin()" class="w-full bg-blue-600 text-white py-3 rounded-xl font-bold hover:bg-blue-700 shadow-lg shadow-blue-200 active:scale-95 transition-all">登录系统</button>
            </div>
        </div>
    </div>

    <nav class="bg-white border-b h-16 sticky top-0 z-10">
        <div class="max-w-5xl mx-auto px-4 h-full flex items-center justify-between">
            <div class="flex items-center space-x-2 font-bold text-xl"><i class="fas fa-square-root-variable text-blue-600"></i><span>MathHub</span></div>
            <button onclick="logout()" class="text-slate-400 hover:text-red-500 transition-colors"><i class="fas fa-power-off"></i></button>
        </div>
    </nav>

    <main id="main-content" class="max-w-4xl mx-auto px-4 py-8 space-y-8 hidden">
        <section class="bg-white rounded-3xl shadow-sm border p-8">
            <div onclick="document.getElementById('file').click()" class="border-2 border-dashed border-slate-200 rounded-2xl p-10 text-center hover:bg-slate-50 cursor-pointer transition-all group">
                <input type="file" id="file" class="hidden" accept=".html">
                <i class="fas fa-cloud-arrow-up text-4xl text-slate-300 group-hover:text-blue-500 mb-4 transition-colors"></i>
                <p id="fname" class="text-slate-500 font-medium">点击或拖拽 HTML 课件到此处</p>
            </div>
            <button onclick="upload()" id="ubtn" class="w-full mt-6 bg-slate-900 text-white py-4 rounded-2xl font-bold hover:bg-slate-800 transition-all flex items-center justify-center space-x-2">
                <i class="fas fa-rocket"></i><span>发布到云端</span>
            </button>
        </section>

        <div id="list" class="grid grid-cols-1 md:grid-cols-2 gap-4"></div>
    </main>

    <script>
        const overlay = document.getElementById('login-overlay');
        const main = document.getElementById('main-content');
        
        // 检查本地登录状态
        if(sessionStorage.getItem('math-auth')) { overlay.style.display = 'none'; main.classList.remove('hidden'); fetchList(); }

        async function doLogin() {
            const pass = document.getElementById('login-pass').value;
            const res = await fetch("/api/login", { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({password: pass}) });
            if(res.ok) { sessionStorage.setItem('math-auth', 'true'); location.reload(); }
            else alert("密码错误！");
        }

        function logout() { sessionStorage.removeItem('math-auth'); location.reload(); }

        async function fetchList() {
            const res = await fetch("/api/list");
            const data = await res.json();
            document.getElementById('list').innerHTML = data.map(i => `
                <div class="bg-white p-6 rounded-2xl border flex flex-col justify-between shadow-sm hover:shadow-md transition-shadow group">
                    <div>
                        <div class="text-[10px] font-bold text-blue-500 mb-1 uppercase tracking-widest">COURSEWARE</div>
                        <h4 class="font-bold text-slate-800 truncate mb-4">${i.name}</h4>
                    </div>
                    <div class="flex items-center justify-between mt-auto">
                        <a href="/u/${i.id}/" target="_blank" class="text-blue-600 font-bold text-sm hover:underline italic underline-offset-4">OPEN LINK</a>
                        <button onclick="del('${i.id}')" class="text-slate-300 hover:text-red-500 transition-colors"><i class="fas fa-trash-alt text-xs"></i></button>
                    </div>
                </div>`).join('');
        }

        async function upload() {
            const f = document.getElementById('file').files[0]; if(!f) return;
            const b = document.getElementById('ubtn'); b.disabled = true; b.innerText = "正在同步...";
            const fd = new FormData(); fd.append("html", f);
            await fetch("/upload", { method: "POST", body: fd });
            location.reload();
        }

        async function del(id) {
            if(!confirm("确定永久删除？")) return;
            await fetch("/delete", { method: "POST", headers: {'Content-Type':'application/json'}, body: JSON.stringify({id}) });
            fetchList();
        }
        document.getElementById('file').onchange = (e) => { if(e.target.files[0]) document.getElementById('fname').innerText = e.target.files[0].name; };
    </script>
</body>
</html>
EON
}

update_nginx() {
    echo "正在重置 Nginx 配置..."
    rm -f /etc/nginx/sites-enabled/html_uploader.conf
    rm -f /etc/nginx/sites-available/html_uploader.conf
    cat > "$NGINX_CONF" << EON
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 50M;
    location / {
        proxy_pass http://127.0.0.1:7878;
        proxy_set_header Host \$host;
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
    echo -e "=== MathHub 终极管理 v4.5 ==="
    echo " 1. 部署/修复 (含精美登录页)"
    echo " 2. 修改登录密码"
    echo " 3. 查看运行日志"
    echo " 0. 退出"
    read -p "选择: " num
    case "$num" in
        1) cd $APP_DIR; npm install express multer --save; write_files; update_nginx; pm2 restart all 2>/dev/null || pm2 start server.js --name $PM2_NAME; echo "完成！"; ;;
        2) read -p "新密码: " np; sed -i "s/let AUTH_PASS = \".*\";/let AUTH_PASS = \"$np\";/" $APP_DIR/server.js; pm2 restart $PM2_NAME; echo "密码已更新"; ;;
        3) pm2 logs $PM2_NAME ;;
        0) exit 0 ;;
    esac
    read -p "回车继续..."
done
EOF

chmod +x /usr/local/bin/webtool
webtool
