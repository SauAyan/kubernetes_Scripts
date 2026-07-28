import time
import json
import os
from fastapi import FastAPI
import uvicorn

app = FastAPI()

CONFIG_PATH = "/app/config/settings.json"
current_config = {}
last_mtime = 0

def load_config():
    """Reads the JSON config file from the mounted ConfigMap volume."""
    global current_config, last_mtime
    try:
        if os.path.exists(CONFIG_PATH):
            # Check last modification time
            mtime = os.path.getmtime(CONFIG_PATH)
            if mtime != last_mtime:
                with open(CONFIG_PATH, "r") as f:
                    current_config = json.load(f)
                last_mtime = mtime
                print(f"[HOT-RELOAD] Configuration updated live at {time.ctime()}: {current_config}")
    except Exception as e:
        print(f"[ERROR] Failed to read config: {e}")

@app.get("/")
def get_config():
    # Reload if the file on disk changed
    load_config()
    return {
        "status": "running",
        "live_config": current_config
    }

if __name__ == "__main__":
    load_config()
    uvicorn.run(app, host="0.0.0.0", port=8000)