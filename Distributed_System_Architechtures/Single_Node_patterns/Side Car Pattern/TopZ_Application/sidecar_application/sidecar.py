import os
import psutil
from fastapi import FastAPI
from fastapi.responses import HTMLResponse

app = FastAPI()

def get_target_process_stats():
    # Look for the uvicorn process running in the shared process namespace
    for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'cpu_percent', 'memory_info']):
        try:
            cmdline = " ".join(proc.info['cmdline'] or [])
            if "uvicorn" in cmdline or "main:app" in cmdline:
                # Fetch CPU and Memory usage
                cpu = proc.cpu_percent(interval=0.1)
                mem = proc.memory_info().rss / (1024 * 1024)  # Convert bytes to MB
                return {"status": "Running", "pid": proc.info['pid'], "cpu_percent": cpu, "memory_mb": round(mem, 2)}
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return {"status": "Process Not Found", "cpu_percent": 0, "memory_mb": 0}

@app.get("/", response_class=HTMLResponse)
def dashboard():
    stats = get_target_process_stats()
    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>FastAPI Resource Monitor</title>
        <meta http-equiv="refresh" content="3"> <!-- Auto refresh every 3s -->
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; background-color: #f4f4f9; }}
            .card {{ background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); width: 300px; }}
            .metric {{ font-size: 24px; font-weight: bold; color: #333; margin-top: 10px; }}
            .label {{ font-size: 14px; color: #666; }}
        </style>
    </head>
    <body>
        <div class="card">
            <h2>FastAPI Sidecar Monitor</h2>
            <p><span class="label">Status:</span> <b>{stats['status']}</b></p>
            <div class="metric">{stats['cpu_percent']}%</div>
            <div class="label">CPU Usage</div>
            <hr>
            <div class="metric">{stats['memory_mb']} MB</div>
            <div class="label">Memory Usage (RSS)</div>
        </div>
    </body>
    </html>
    """