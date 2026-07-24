import random
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def get_random_number():
    return {"random_number": random.randint(1, 100)}