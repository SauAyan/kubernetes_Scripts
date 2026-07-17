| Label Key | Purpose / Hierarchy Level | Example |
| :--- | :--- | :--- |
| **`app.kubernetes.io/name`** | The Application: The name of the overall application. | `mysql`, `payment-gateway` |
| **`app.kubernetes.io/instance`** | The Instance: A unique name identifying this specific deployment instance. | `payment-gateway-prod-01` |
| **`app.kubernetes.io/component`** | The Architecture Layer: The specific component within the architecture. | `database`, `frontend`, `api` |
| **`app.kubernetes.io/part-of`** | The Umbrella Ecosystem: The larger solution/product this application belongs to. | `e-commerce-suite` |
| **`app.kubernetes.io/version`** | The Release Version: The current version of the software. | `1.4.2`, `v2.0-beta` |
| **`app.kubernetes.io/managed-by`** | The Controller: The tool used to manage the operation. | `helm`, `argo-cd`, `terraform` |