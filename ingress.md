This manifest and the accompanying curl commands set up and test a complete, end-to-end web application traffic flow inside your Kubernetes cluster using the **Ingress** concept we just broke down.

Here is exactly what each block does and how the traffic moves when you run that test loop:

---

## Part 1: The Manifest Breakdown

### 1. The Content Layer (`ConfigMap`)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-v1
data:
  index.html: |
    <html><body><h1>Hello from V1</h1></body></html>

```

* **What it does:** It acts as a mini key-value storage system inside Kubernetes.
* **Why it's here:** It holds a static HTML string (`Hello from V1`). This allows you to change the webpage content dynamically without rebuilding the container image.

### 2. The Application Layer (`Deployment`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
...

```

* **What it does:** It runs **3 exact replicas** (pods) of an Nginx web server.
* **The Magic Link:** Look at the `volumes` and `volumeMounts` section. It takes the `index.html` file stored in the `web-v1` ConfigMap above and injects (**mounts**) it directly into Nginx's default web directory (`/usr/share/nginx/html/index.html`). Now, all 3 pods serve your custom "Hello from V1" webpage.

### 3. The Internal Routing Layer (`Service`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80

```

* **What it does:** This creates a stable internal IP address and a built-in internal load balancer named `web`.
* **Why it's here:** It sits in front of your 3 Nginx pods. When traffic hits this service on port 80, it cleanly alternates and distributes the load among the 3 running pods.

### 4. The Entry Point Layer (`Ingress`)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
...
spec:
  ingressClassName: nginx
  rules:
    - host: base.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80

```

* **What it does:** This is the edge router configuration we discussed earlier. It tells your cluster's **Ingress Controller**:
> *"If an external user types the domain **`base.com`** into their browser and hits the root path (`/`), intercept that traffic and forward it internally to our **`web`** Service on port 80."*



---

## Part 2: The Test Commands (`curl`)

```bash
curl --resolve base.com:80:192.168.10.0 http://base.com:80

```

Because `base.com` isn't a real internet domain registered to your local VMware environment, your computer wouldn't normally know where to send this request.

The `--resolve` flag acts as a **temporary local DNS override**. It tells curl: *"Do not look up `base.com` on the internet. Forcefully send this packet directly to the IP address **`192.168.10.0`** (which is your cluster's External Load Balancer / Ingress Entry Point), but leave the domain header inside the packet as `base.com` so the Ingress Controller knows how to route it."*

```bash
while true; do curl --resolve base.com:80:192.168.10.0 http://base.com:80 ; done

```

This is an infinite bash loop. It will spam the endpoint with requests nonstop. When you run this, your terminal will instantly flood with:

```html
<html><body><h1>Hello from V1</h1></body></html>
<html><body><h1>Hello from V1</h1></body></html>
<html><body><h1>Hello from V1</h1></body></html>

```

### Why this is perfect for your setup:

This loop is exactly how you can **load test your HPA (Horizontal Pod Autoscaler)**. If you run this loop from your jump server, it will generate enough continuous traffic to spike the CPU of those 3 Nginx pods, allowing you to watch your HPA scale them up to 10 replicas in real-time!