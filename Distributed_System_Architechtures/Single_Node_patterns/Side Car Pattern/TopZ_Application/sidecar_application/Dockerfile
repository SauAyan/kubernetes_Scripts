FROM python:3.11-slim

WORKDIR /app

# Install psutil (requires procps for reading /proc)
RUN apt-get update && apt-get install -y procps && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sidecar.py .

EXPOSE 8080

CMD ["uvicorn", "sidecar:app", "--host", "0.0.0.0", "--port", "8080"]