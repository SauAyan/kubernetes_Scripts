# Implementing SideCar to run Top Command in a container running on the same Pod
#### Containers have to be coupled
##### 1. Main Application: Generates a Random Number
##### 2. SideCar Application: Checks resources used by the main appliacation

# We can change the application Codes but keep coupling it with sidecar to get the data. Even if application is not in python, this setup will work

# Copy application from Jump Server to manager node
scp -r sidecar_demo azureuser@10.0.1.10:sidecar_demo

### Steps To Run

kubectl apply -f side_car_application.yaml

# Detailed Process
Pushing your images to a container registry (Hub) and referencing them in your Kubernetes YAML is the **standard industry best practice** for multi-node clusters.

Here is the step-by-step workflow using **Docker Hub** (or any public/private registry like GitHub Container Registry, Quay.io, or Azure Container Registry).

---

## Step 1: Login to Docker Hub on `k8s-manager`

On your manager node, log in to your Docker Hub account using `podman`:

```bash
sudo podman login docker.io

```

*(Enter your Docker Hub username and password/access token when prompted)*

---

## Step 2: Build and Tag Your Images

Tag the images using your **Docker Hub username** (`<your-dockerhub-username>`):

```bash
# Build & tag main_application
sudo podman build -t <your-dockerhub-username>/main_application:v1 ./main_application

# Build & tag sidecar_application
sudo podman build -t <your-dockerhub-username>/sidecar_application:v1 ./sidecar_application

```

---

## Step 3: Push Images to Docker Hub

Push both images to your Docker Hub repository:

```bash
sudo podman push <your-dockerhub-username>/main_application:v1
sudo podman push <your-dockerhub-username>/sidecar_application:v1

```

Now the images live on Docker Hub, so any worker node (`k8s-node-1`, `k8s-node-2`, `k8s-node-3`) can pull them over the internet automatically!

---

## Step 4: Update Your `side_car_application.yaml`

Clean up all `hostPath` mounts, `command` overrides, and point the container images directly to Docker Hub:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: main-sidecar-app
  namespace: learning
  labels:
    app: fastapi-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fastapi-system
  template:
    metadata:
      labels:
        app: fastapi-system
    spec:
      shareProcessNamespace: true
      
      containers:
      # 1. Main Application Container
      - name: main-application
        image: <your-dockerhub-username>/main_application:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
          name: api-port

      # 2. Sidecar Application Container
      - name: sidecar-application
        image: <your-dockerhub-username>/sidecar_application:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: monitor-port

---
apiVersion: v1
kind: Service
metadata:
  name: main-app-service
  namespace: learning
spec:
  type: ClusterIP
  selector:
    app: fastapi-system
  ports:
    - protocol: TCP
      port: 8000
      targetPort: 8000
      name: http-api

---
apiVersion: v1
kind: Service
metadata:
  name: sidecar-monitor-service
  namespace: learning
spec:
  type: ClusterIP
  selector:
    app: fastapi-system
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
      name: http-monitor

```

*(Remember to replace `<your-dockerhub-username>` with your actual Docker Hub username).*

---

## Step 5: Deploy to Kubernetes

Apply the clean YAML:

```bash
kubectl apply -f side_car_application.yaml

```

Check the status:

```bash
kubectl get pods -n learning -l app=fastapi-system -o wide

```

Each worker node will pull the images straight from Docker Hub and start the containers smoothly regardless of where the pod is scheduled!