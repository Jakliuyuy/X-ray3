# Xray Proxy Manager

基于 FastAPI + React + Tailwind CSS 的 Xray 节点管理前后端项目

## 环境要求
- Python 3.8+
- Node.js 16+
- Debian 12（后端需有 systemctl 权限）

## 后端启动

1. 安装依赖
```bash
cd backend
pip install -r requirements.txt
```

2. 启动 FastAPI 服务
```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

> 如需管理 /etc/xray/config.json 和重启 Xray，需以有权限用户运行。

## 前端启动

1. 安装依赖
```bash
cd frontend
npm install
```

2. 启动开发环境
```bash
npm run dev
```

3. 打包静态文件
```bash
npm run build
```

> 打包后 dist 目录可部署到 Nginx。

## 主要功能
- 用户管理（添加/删除/展示）
- 节点连接展示（vless 链接、二维码、一键复制）
- 订阅生成（Clash YAML、V2Ray Base64）
- 系统状态展示（用户数、端口、协议、Xray 在线状态）
- 暗色模式切换

## API 示例
- `POST /api/user` 添加用户
- `GET /api/users` 用户列表
- `DELETE /api/user/{uuid}` 删除用户
- `GET /api/subscribe/clash` Clash 订阅
- `GET /api/subscribe/v2ray` V2Ray 订阅
- `GET /api/status` 系统状态

## 部署建议
- 后端建议用 systemd 管理
- 前端静态文件建议用 Nginx 部署
- HTTPS 可用 Nginx + Certbot

---
如有问题欢迎 issue 或 PR！
