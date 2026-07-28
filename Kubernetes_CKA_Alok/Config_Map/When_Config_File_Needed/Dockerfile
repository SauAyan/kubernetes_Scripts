FROM python:3.11-slim

WORKDIR /app

# Install FastAPI and Uvicorn
RUN pip install --no-cache-dir fastapi uvicorn

# Copy the app.py script into the image
COPY app.py .

# Create the config directory where the ConfigMap volume will mount
RUN mkdir -p /app/config

# Run app.py
CMD ["python", "app.py"]