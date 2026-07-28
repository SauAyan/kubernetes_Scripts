FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir fastapi uvicorn

COPY main.py .

# Use shell form so $APP_PORT is evaluated at runtime
CMD ["sh", "-c", "python main.py"]