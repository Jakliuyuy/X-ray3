cat > /usr/local/bin/webtool << 'EOF'
#!/bin/bash
# =========================================================
#  MathHub 汉化增强版 (v4.6) - 全中文界面
# =========================================================

DOMAIN="math.liuyuy.xyz"
APP_DIR="/var/www/html-uploader"
PM2_NAME="html-uploader"
NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"

[[ $EUID -ne 0 ]] && echo "请用 root 运行" && exit 1

write_files() {
    mkdir -p $APP_DIR/{uploads,public}
    
    # 1. 后端 server.js (保持逻辑不变)
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

let AUTH_PASS = "123456"; 

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

    # 2. 前端 index.html (汉化完成)
    cat > $APP_DIR/public/index.html << 'EON'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>数学教学课件管理平台</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
</head>
<body class="bg-slate-50 min-h-screen text-slate-800">
    <div id="login-overlay" class="fixed inset-0 z-[100] bg-slate-900 flex items-center justify-center p-4">
        <div class="bg-white w-full max-w-sm rounded-3xl shadow-2xl overflow-hidden">
            <div class="bg-blue-600 p-8 text-white text-center">
                <div class="w-16 h-16 bg-white/20 rounded-2xl flex items-center justify-center mx-auto mb-4">
                    <i class="fas fa-user-shield text-2xl"></i>
                </div>
                <h2 class="text-2xl font-bold">后台管理登录</h2>
                <p class="text-blue-100 mt-1 text-sm">请输入管理员密码访问</p>
            </div>
            <div class="p-8">
                <input type="password" id="login-pass" class="w-full px-4 py-3 rounded-xl border border-slate-200 focus:ring-2 focus:ring-blue-500 outline-none mb-4" placeholder="请输入密码">
                <button onclick="doLogin()" class="w-full bg-blue-600 text-white py-3 rounded-xl font-bold hover:bg-blue-700 shadow-lg active:scale-95 transition-all text-lg">进入系统</button>
            </div>
        </div>
    </div>

    <nav class="bg-white border-b h-16 sticky top-0 z-10">
        <div class="max-w-5xl mx-auto px-4 h-full flex items-center justify-between">
            <div class="flex items-center space-x-2 font-bold text-xl"><i class="fas fa-calculator text-blue-600"></i><span>数学课件云平台</span></div>
            <button onclick="logout()" class="text-slate-400 hover:text-red-500 flex items-center space-x-1">
                <span class="text-xs">退出登录</span><i class="fas fa-sign-out-alt"></i>
            </button>
        </div>
    </nav>

    <main id="main-content" class="max-w-4xl mx-auto px-4 py-8 space-y-8 hidden">
        <section class="bg-white rounded-3xl shadow-sm border p-8">
            <div onclick="document.getElementById('file').click()" class="border-2 border-dashed border-slate-200 rounded-2xl p-10 text-center hover:bg-slate-50 cursor-pointer transition-all group">
                <input type="file" id="file" class="hidden" accept=".html">
                <i class="fas fa-file-export text-4xl text-slate-300 group-hover:text-blue-500 mb-4"></i>
                <p id="fname" class="text-slate-500 font-medium">点击此处或将课件拖拽到这里上传</p>
            </div>
            <button onclick="upload()" id="ubtn" class="w-full mt-6 bg-slate-900 text-white py-4 rounded-2xl font-bold hover:bg-slate-800 transition-all flex items-center justify-center space-x-2">
                <i class="fas fa-cloud-arrow-up"></i><span>立即发布到云端</span>
            </button>
        </section>

        <div class="flex items-center space-x-2 mb-2 px-2">
            <i class="fas fa-folder-open text-blue-500"></i><h3 class="font-bold text-lg">已发布的课件</h3>
        </div>
        <div id="list" class="grid grid-cols-1 md:grid-cols-2 gap-4"></div>
    </main>

    <script>
        const overlay = document.getElementById('login-overlay');
        const main = document.getElementById('main-content');
        
        if(sessionStorage.getItem('math-auth')) { overlay.style.display = 'none'; main.classList.remove('hidden'); fetchList(); }

        async function doLogin() {
            const pass = document.getElementById('login-pass').value;
            const res = await fetch("/api/login", { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({password: pass}) });
            if(res.ok) { sessionStorage.setItem('math-auth', 'true'); location.reload(); }
            else alert("登录密码不正确，请重试！");
        }

        function logout() { sessionStorage.removeItem('math-auth'); location.reload(); }

        async function fetchList() {
            const res = await fetch("/api/list");
            const data = await res.json();
            document.getElementById('list').innerHTML = data.map(i => `
                <div class="bg-white p-6 rounded-2xl border flex flex-col justify-between shadow-sm hover:shadow-md transition-shadow">
                    <div>
                        <div class="text-[10px] font-bold text-blue-500 mb-1 uppercase tracking-widest">数学课件资源</div>
                        <h4 class="font-bold text-slate-800 truncate mb-1" title="${i.name}">${i.name}</h4>
                        <p class="text-[11px] text-slate-400 mb-4 italic">${i.date}</p>
                    </div>
                    <div class="flex items-center justify-between mt-auto">
                        <a href="/u/${i.id}/" target="_blank" class="bg-blue-50 text-blue-600 px-4 py-2 rounded-lg font-bold text-xs hover:bg-blue-600 hover:text-white transition-all">
                            打开课件 <i class="fas fa-external-link-alt ml-1"></i>
                        </a>
                        <button onclick="del('${i.id}')" class="text-slate-300 hover:text-red-500 transition-colors px-2 py-1">
                            <i class="fas fa-trash-alt text-xs"></i>
                        </button>
                    </div>
                </div>`).join('');
        }

        async function upload() {
            const f = document.getElementById('file').files[0]; if(!f) return;
            const b = document.getElementById('ubtn'); b.disabled = true; b.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 正在上传...';
            const fd = new FormData(); fd.append("html", f);
            await fetch("/upload", { method: "POST", body: fd });
            location.reload();
        }

        async function del(id) {
            if(!confirm("确定要永久删除这份课件吗？")) return;
            await fetch("/delete", { method: "POST", headers: {'Content-Type':'application/json'}, body: JSON.stringify({id}) });
            fetchList();
        }
        document.getElementById('file').onchange = (e) => { if(e.target.files[0]) document.getElementById('fname').innerHTML = `<span class="text-blue-600 font-bold">${e.target.files[0].name}</span>`; };
    </script>
</body>
</html>
EON
}

update_nginx() {
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
    echo -e "=== 数学课件云平台管理菜单 v4.6 ==="
    echo " 1. 部署/更新 (应用中文界面)"
    echo " 2. 修改后台登录密码"
    echo " 3. 查看系统运行状态"
    echo " 0. 退出管理"
    read -p "请输入指令: " num
    case "$num" in
        1) cd $APP_DIR; npm install express multer --save; write_files; update_nginx; pm2 restart all 2>/dev/null || pm2 start server.js --name $PM2_NAME; echo "更新完成！"; ;;
        2) read -p "请输入新密码: " np; sed -i "s/let AUTH_PASS = \".*\";/let AUTH_PASS = \"$np\";/" $APP_DIR/server.js; pm2 restart $PM2_NAME; echo "密码修改成功！"; ;;
        3) pm2 status; pm2 logs $PM2_NAME --lines 20 ;;
        0) exit 0 ;;
    esac
    read -p "回车键返回..."
done
EOF

chmod +x /usr/local/bin/webtool
webtool
