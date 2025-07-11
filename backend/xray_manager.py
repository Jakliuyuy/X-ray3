import json
import os

XRAY_CONFIG_PATH = "/etc/xray/config.json"

# 读取配置文件
def load_config():
    with open(XRAY_CONFIG_PATH, "r") as f:
        return json.load(f)

# 写入配置文件
def save_config(config):
    with open(XRAY_CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)

# 添加/删除用户等操作可在此实现
