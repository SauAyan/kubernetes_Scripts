import os
import uvicorn
from fastapi import FastAPI

app = FastAPI()

# Read settings from ConfigMap environment variables
ENV_NAME = os.getenv("APP_ENV", "local")
PORT = int(os.getenv("APP_PORT", "8000"))
DB_HOST = os.getenv("DB_HOST", "localhost")
ENABLE_DISCOUNTS = os.getenv("ENABLE_DISCOUNTS", "false").lower() == "true"

@app.get("/")
def get_status():
    return {
        "status": "online",
        "environment": ENV_NAME,
        "database_host": DB_HOST,
        "feature_discounts_enabled": ENABLE_DISCOUNTS,
        "running_on_port": PORT
    }

@app.get("/orders")
def list_orders():
    orders = [{"id": 101, "item": "Laptop", "price": 1200}]
    if ENABLE_DISCOUNTS:
        orders[0]["discounted_price"] = 1080
    return {"orders": orders}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)