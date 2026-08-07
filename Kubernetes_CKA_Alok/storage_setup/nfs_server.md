Yes. We can set up one worker node as an NFS server without disturbing the running Kubernetes workloads. For your lab, use `k8s-worker-3` at `10.0.1.13`.

The safest approach is:

* Do not change Kubernetes configuration.
* Do not drain or restart the node.
* Use a separate directory for NFS data.
* Restrict NFS access to your cluster subnet only.
* Install only the NFS packages.

Ubuntu provides the `nfs-kernel-server` package for hosting NFS shares, while Kubernetes nodes require the NFS mount helper to mount those shares. ([Ubuntu][1])

## Step 1: Connect to the NFS worker

From the gateway:

```bash
ssh azureuser@10.0.1.13
```

Confirm that you are on the correct node:

```bash
hostname
hostname -I
```

Expected:

```text
k8s-worker-3
10.0.1.13
```

Also check that the node has enough disk space:

```bash
df -h /
```

Do not proceed if the root disk is nearly full.

## Step 2: Install the NFS server package

On `k8s-worker-3`:

```bash
sudo apt update
sudo apt install -y nfs-kernel-server
```

This installation should not restart Kubernetes, containerd, kubelet, or your running pods.

Check the service:

```bash
sudo systemctl status nfs-kernel-server --no-pager
```

You may see it active or waiting for an export configuration. That is normal at this stage.

## Step 3: Create a dedicated NFS directory

Create a directory used only for Kubernetes storage:

```bash
sudo mkdir -p /srv/nfs/kubernetes
```

For a simple lab demonstration, allow containers to write to it:

```bash
sudo chown nobody:nogroup /srv/nfs/kubernetes
sudo chmod 0777 /srv/nfs/kubernetes
```

`0777` is acceptable for this isolated demo, but it is not recommended for sensitive production data.

Verify:

```bash
ls -ld /srv/nfs/kubernetes
```

Expected permissions should resemble:

```text
drwxrwxrwx ... nobody nogroup ... /srv/nfs/kubernetes
```

## Step 4: Back up the existing exports file

Before changing anything:

```bash
sudo cp /etc/exports /etc/exports.backup
```

Check whether it already contains exports:

```bash
sudo cat /etc/exports
```

## Step 5: Export the directory only to the cluster subnet

Edit the exports file:

```bash
sudo nano /etc/exports
```

Add this line:

```text
/srv/nfs/kubernetes 10.0.1.0/24(rw,sync,no_subtree_check,no_root_squash)
```

Meaning:

* `10.0.1.0/24`: only your Kubernetes subnet can access it.
* `rw`: clients can read and write.
* `sync`: changes are written safely before responses are returned.
* `no_subtree_check`: avoids subtree verification issues.
* `no_root_squash`: allows root inside a pod to write as root on the share.

For a lab this is convenient. In production, `no_root_squash` should be reviewed carefully.

Save in Nano with:

```text
Ctrl+O
Enter
Ctrl+X
```

## Step 6: Activate the export

Run:

```bash
sudo exportfs -rav
```

Expected output:

```text
exporting 10.0.1.0/24:/srv/nfs/kubernetes
```

Restart the NFS server:

```bash
sudo systemctl restart nfs-kernel-server
```

Enable it after reboot:

```bash
sudo systemctl enable nfs-kernel-server
```

Verify:

```bash
sudo exportfs -v
```

You should see `/srv/nfs/kubernetes`.

## Step 7: Check that NFS is listening

Run:

```bash
sudo ss -lntup | grep -E '2049|111'
```

The important NFS port is:

```text
2049
```

Also verify locally:

```bash
showmount -e localhost
```

Expected:

```text
Export list for localhost:
/srv/nfs/kubernetes 10.0.1.0/24
```

## Step 8: Install NFS client utilities on every Kubernetes node

Kubernetes uses the host operating system's NFS mount helper. Therefore, install `nfs-common` on:

* `k8s-manager`
* `k8s-worker-1`
* `k8s-worker-2`
* `k8s-worker-3`

Kubernetes documentation notes that `/sbin/mount.nfs` must exist on nodes that may mount an NFS PersistentVolume. ([Kubernetes][2])

From the gateway, connect to each node one at a time:

```bash
ssh azureuser@10.0.1.10
sudo apt update
sudo apt install -y nfs-common
exit
```

Then:

```bash
ssh azureuser@10.0.1.11
sudo apt update
sudo apt install -y nfs-common
exit
```

Then:

```bash
ssh azureuser@10.0.1.12
sudo apt update
sudo apt install -y nfs-common
exit
```

Then:

```bash
ssh azureuser@10.0.1.13
sudo apt install -y nfs-common
exit
```

Installing `nfs-common` does not restart Kubernetes workloads.

## Step 9: Test the share manually from another worker

Connect to `k8s-worker-1`:

```bash
ssh azureuser@10.0.1.11
```

Create a temporary mount directory:

```bash
sudo mkdir -p /mnt/nfs-test
```

Mount the share:

```bash
sudo mount -t nfs 10.0.1.13:/srv/nfs/kubernetes /mnt/nfs-test
```

Create a test file:

```bash
echo "NFS test from worker-1" | sudo tee /mnt/nfs-test/test.txt
```

Read it:

```bash
cat /mnt/nfs-test/test.txt
```

Unmount after testing:

```bash
sudo umount /mnt/nfs-test
sudo rmdir /mnt/nfs-test
```

This manual mount is only a connectivity test. Do not add it to `/etc/fstab`; Kubernetes will mount the share when pods need it.

## Step 10: Create a Kubernetes PersistentVolume and claim

Return to the manager or gateway where `kubectl` works.

Create:

```bash
nano nfs-storage-demo.yaml
```

Add:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-demo-pv
spec:
  capacity:
    storage: 5Gi

  accessModes:
    - ReadWriteMany

  persistentVolumeReclaimPolicy: Retain

  storageClassName: nfs-manual

  mountOptions:
    - nfsvers=4.1

  nfs:
    server: 10.0.1.13
    path: /srv/nfs/kubernetes

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-demo-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany

  storageClassName: nfs-manual

  resources:
    requests:
      storage: 5Gi
```

Apply:

```bash
kubectl apply -f nfs-storage-demo.yaml
```

Check:

```bash
kubectl get pv
kubectl get pvc
```

Expected:

```text
nfs-demo-pv    Bound
nfs-demo-pvc   Bound
```

An NFS volume can be mounted into Kubernetes pods and supports shared access across nodes. ([Kubernetes][3])

## Step 11: Test with pods on different nodes

Create:

```bash
nano nfs-pod-demo.yaml
```

Add:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-demo
spec:
  replicas: 3

  selector:
    matchLabels:
      app: nfs-demo

  template:
    metadata:
      labels:
        app: nfs-demo

    spec:
      containers:
        - name: nginx
          image: nginx:stable-alpine

          ports:
            - containerPort: 80

          volumeMounts:
            - name: shared-storage
              mountPath: /usr/share/nginx/html

      volumes:
        - name: shared-storage
          persistentVolumeClaim:
            claimName: nfs-demo-pvc

---
apiVersion: v1
kind: Service
metadata:
  name: nfs-demo
spec:
  selector:
    app: nfs-demo

  ports:
    - port: 80
      targetPort: 80
```

Apply:

```bash
kubectl apply -f nfs-pod-demo.yaml
```

Check where the pods are running:

```bash
kubectl get pods -l app=nfs-demo -o wide
```

Create shared HTML content through one pod:

```bash
POD=$(kubectl get pod -l app=nfs-demo -o jsonpath='{.items[0].metadata.name}')

kubectl exec "$POD" -- sh -c \
  'echo "<h1>Hello from shared NFS storage</h1>" > /usr/share/nginx/html/index.html'
```

Read it from every replica:

```bash
for pod in $(kubectl get pods -l app=nfs-demo -o name); do
  echo "Testing $pod"
  kubectl exec "$pod" -- cat /usr/share/nginx/html/index.html
done
```

Every pod should show the same content.

## Important precautions

Do not:

* Store NFS data under `/var/lib/kubelet`.
* Modify containerd or kubelet configuration.
* export the entire root filesystem.
* expose NFS to `0.0.0.0/0`.
* restart or drain the node unless necessary.
* use this single-node NFS design for production-critical storage.

Because the NFS server is also a worker, workloads on other nodes will temporarily lose access if `k8s-worker-3` is stopped. Existing Kubernetes workloads that do not use this NFS share will continue working normally.

[1]: https://ubuntu.com/server/docs/how-to/networking/install-nfs/?utm_source=chatgpt.com "Network File System (NFS) - Ubuntu Server documentation"
[2]: https://kubernetes.io/docs/concepts/storage/persistent-volumes/?force_isolation=true&utm_source=chatgpt.com "Persistent Volumes | Kubernetes"
[3]: https://kubernetes.io/docs/concepts/storage/volumes/?q=configmap&utm_source=chatgpt.com "Volumes | Kubernetes"
