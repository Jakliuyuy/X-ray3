from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uuid
import json
import os
import subprocess
from typing import List

XRAY_CONFIG_PATH = "/etc/xray/config.json"

app = FastAPI()


# 系统状态接口
@app.get("/api/status")
def get_status():
    user_count = len(users)
    port = 443
    protocol = "vless"
    try:
        result = subprocess.run(["systemctl", "is-active", "xray"], capture_output=True, text=True)
        online = result.stdout.strip() == "active"
    except Exception:
        online = False
    return {
        "user_count": user_count,
        "port": port,
        "protocol": protocol,
        "xray_online": online
    }


class User(BaseModel):
    uuid: str
    remark: str
    vless: str = None

class UserCreate(BaseModel):
    remark: str

# 内存模拟用户列表，后续可改为读取 config.json
users = []

@app.post("/api/user", response_model=User)
def add_user(user: UserCreate):
    new_uuid = str(uuid.uuid4())
    # vless 链接生成示例，实际端口/域名请根据你的配置调整
    domain = "your.domain.com"
    port = 443
    vless_link = f"vless://{new_uuid}@{domain}:{port}?encryption=none#" + user.remark
    new_user = User(uuid=new_uuid, remark=user.remark, vless=vless_link)
    users.append(new_user)
    # 写入 XRAY_CONFIG_PATH 并重启服务
    update_xray_config(users)
    restart_xray_service()
    return new_user

@app.get("/api/users", response_model=List[User])
def get_users():
    return users

@app.delete("/api/user/{uuid}")
def delete_user(uuid: str):
    global users
    users = [u for u in users if u.uuid != uuid]
    update_xray_config(users)
    restart_xray_service()
    return {"result": "ok"}
# 写入 XRAY 配置文件
def update_xray_config(user_list):
    # 这里只是示例，实际需根据你的 Xray 配置结构调整
    config = {
        "inbounds": [
            {
                "port": 443,
                "protocol": "vless",
                "settings": {
                    "clients": [
                        {"id": u.uuid, "email": u.remark} for u in user_list
                    ]
                }
            }
        ]
    }
    with open(XRAY_CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)

# 重启 Xray 服务
def restart_xray_service():
    try:
        subprocess.run(["systemctl", "restart", "xray"], check=True)
    except Exception as e:
        print("Xray 重启失败:", e)

@app.get("/api/subscribe/clash")
def get_clash_subscribe():
    # 生成 Clash YAML
    proxies = []
    for u in users:
        proxies.append({
            "name": u.remark,
            "type": "vless",
            "server": "your.domain.com",  # 可改为实际域名
            "port": 443,
            "uuid": u.uuid,
            "encryption": "none",
            "network": "tcp"
        })
    clash_yaml = {
        "proxies": proxies,
        "proxy-groups": [
            {
                "name": "auto",
                "type": "select",
                "proxies": [u.remark for u in users]
            }
        ]
    }
    import yaml
    return yaml.dump(clash_yaml, allow_unicode=True)

@app.get("/api/subscribe/v2ray")
def get_v2ray_subscribe():
    # 生成 V2Ray Base64 订阅（合并所有 vless 链接）
    links = [u.vless for u in users]
    import base64
    b64 = base64.b64encode("\n".join(links).encode()).decode()
    return b64

@app.post("/api/xray/restart")
def restart_xray():
    try:
        subprocess.run(["systemctl", "restart", "xray"], check=True)
        return {"result": "restarted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
