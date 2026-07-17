Creating the file manually via copy-paste is an excellent, straightforward workaround to bypass SSH/`scp` permission restrictions between the nodes.

Here is the cleanest way to do this without messing up the YAML indentation.

---

### Step 1: Get the Config Content from the Manager Node

Log into your **Kubernetes Manager/Control Plane Node** (`10.0.0.101`) and display the contents of the administrative config file:

```bash
sudo cat /etc/kubernetes/admin.conf

```

**Action:** Highlight and copy the entire text output block from your terminal window. It will look similar to this:

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0t...
    server: https://10.0.0.101:6443
  name: kubernetes
contexts:
...

```

---

### Step 2: Create and Paste into the Jump Server

Now, switch over to your **Jump Server**, log in as your regular user (`ayansau`), and follow these steps:

1. Create the hidden `.kube` directory in your home path:
```bash
mkdir -p ~/.kube

```


2. Open a new file named `config` using a terminal text editor:
```bash
vim ~/.kube/config

```


3. **Paste the contents** you copied from Step 1.
*(If using Nano, you can simply right-click to paste or use `Shift + Ctrl + V`).*
4. Save and exit the editor:
* Press `Ctrl + O` then `Enter` to save.
* Press `Ctrl + X` to exit.



---

### Step 3: Secure the File Permissions

Kubernetes will throw a warning or outright refuse to use a config file if its permissions are too open to other users on the system. Restrict it so only your user account can read or write to it:

```bash
chmod 600 ~/.kube/config

```

---

### Step 4: Verify the Connection

Test that your jump server's `kubectl` client can officially authenticate and query your cluster manager:

```bash
kubectl get nodes

```

If everything is correct, it will print out your cluster's complete node topology!