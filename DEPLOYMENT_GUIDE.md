# Deployment Guide – Todo App on AWS EKS

This repository contains a full-stack Todo application (ASP.NET Core API + MongoDB) packaged as a Helm chart.  
Follow this guide to build the container image, deploy to an Amazon EKS cluster, and optionally onboard the chart into ArgoCD.

---

## 1. Prerequisites

| Tool / Account | Purpose | Docs |
|----------------|---------|------|
| AWS account (admin access) | Create EKS cluster, load balancers, EBS volumes | [AWS Console](https://console.aws.amazon.com/) |
| AWS CLI v2 | Interact with AWS from terminal | [Install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| kubectl ≥ 1.28 | Manage Kubernetes resources | [Install](https://kubernetes.io/docs/tasks/tools/) |
| Helm ≥ 3.12 | Package manager for Kubernetes | [Install](https://helm.sh/docs/intro/install/) |
| Docker (optional) | Build the Todo app container locally | [Install](https://docs.docker.com/get-docker/) |
| ghcr.io PAT (optional) | Push images to GitHub Container Registry | [Guide](https://docs.github.com/packages/working-with-a-github-packages-registry/working-with-the-container-registry) |

Verify tools:

```bash
aws --version
kubectl version --client
helm version
docker --version      # optional
```

---

## 2. Build & Push the Todo App Image (optional)

If you want the latest code in the container image, build and push it to GHCR (or another registry you control).  
EKS Auto Mode currently provisions amd64 instances, so always publish a multi-arch image (amd64 + arm64) to avoid `exec format error`.

```bash
# 1. Authenticate to GHCR (replace TOKEN)
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u monswiklund --password-stdin

# 2. Build & push a multi-arch image (use a unique tag per release)
IMAGE_TAG=eks-$(date +%Y%m%d%H%M)  # e.g. eks-20251018
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/monswiklund/todo-app:${IMAGE_TAG} \
  --push \
  .

# 3. (Optional) bump latest if other environments rely on it
docker tag ghcr.io/monswiklund/todo-app:${IMAGE_TAG} ghcr.io/monswiklund/todo-app:latest
docker push ghcr.io/monswiklund/todo-app:latest
```

> Update the Helm release with `--set image.tag=${IMAGE_TAG}` when you deploy.

---

## 3. Create an EKS Cluster (AWS Console, Auto Mode)

1. **Open** the EKS console → *Create cluster* → choose **Quick configuration**.  
   - Name: `eks-cluster-todo` (or any name).  
   - Kubernetes version: latest (e.g. 1.34).  
   - Click *Create recommended role* for both cluster and node roles.

2. **Networking**  
   - Click *Create VPC*. In the VPC wizard:
     - Availability Zones: **2**  
     - Public subnets: **2**  
     - Private subnets: **2**  
     - NAT Gateways: 1 per AZ (required for private nodes to reach the internet).  
     - Add this tag to all subnets: `kubernetes.io/cluster/eks-cluster-todo` value = `shared`
   - Finish VPC creation and go back to EKS → choose the new VPC → EKS auto-selects the two **private** subnets.
   - Create the cluster and wait ~10–15 minutes for status **Active**.

3. **Tag the public subnets** (critical for internet-facing load balancers):
   - In the VPC console → Subnets → find the two **public** subnets (auto-assign public IPv4 = Yes).  
   - Add tag `kubernetes.io/role/elb = 1` to each public subnet.

4. **Configure kubectl** once the cluster is ready:

```bash
aws eks update-kubeconfig --region eu-west-1 --name my-cluster
kubectl get nodes
```

> With Auto Mode you might see “No resources found” until pods are deployed – node provisioning is on-demand.

---

## 4. Deploy the Todo App with Helm

### 4.1 Choose the values file

- **Docker Desktop** (local testing): `charts/todo/values-docker-desktop.yaml`  
- **EKS (GHCR image)**: `charts/todo/values-eks-ghcr.yaml`

### 4.2 Install / upgrade the chart

```bash
# Make sure kubectl points at EKS (avoid deploying to docker-desktop)
kubectl config current-context

# Example for EKS
helm dependency update charts/todo  # no dependencies, but safe

helm upgrade --install todo-app charts/todo \
  -f charts/todo/values-eks-ghcr.yaml \
  --set image.tag=${IMAGE_TAG:-latest}
```

What gets created:

| Resource | Purpose |
|----------|---------|
| Namespace `todo-app` | Isolates application resources |
| StorageClass (optional) | EBS CSI storage class on EKS |
| Service `mongodb-service` | Headless service for StatefulSet |
| StatefulSet `mongodb` | MongoDB with PVC (`mongodb-data`) |
| Job `todo-app-mongodb-init` | Seeds the database with starter todos |
| ConfigMap `webapp-config` | Mongo connection string + ASP.NET settings |
| Service `todo-webapp-service` | Exposes the API/webapp (LB or NodePort) |
| Deployment `todo-webapp` | ASP.NET Core Todo application |
| (Optional) Mongo Express Deployment + Service | Disabled by default (`mongoExpress.enabled: false`) |

### 4.3 Validate the deployment

```bash
# Watch pods come online
kubectl get pods -n todo-app -w

# Check services and external endpoints
kubectl get svc -n todo-app

# For LoadBalancer service: fetch DNS
EXTERNAL_DNS=$(kubectl get svc todo-webapp-service -n todo-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Validate API (quote the URL so spaces/newlines won't break the command)
curl "http://${EXTERNAL_DNS}/todos"
```

When the seeding job completes you should see two default todos returned.

---

## 5. (Optional) Register the Chart in ArgoCD

1. Install ArgoCD (if not already):

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

2. Apply the application manifest:

```bash
kubectl apply -f argocd-app.yaml
```

3. Open the ArgoCD UI (port-forward or LoadBalancer) → login as `admin`.  
   - Sync the `todo-app` application.  
   - Monitor health (Namespace → StorageClass → MongoDB → WebApp).
   - With auto-sync disabled by default you control when updates are applied.

> **Tip:** När du bygger en ny container för EKS/ArgoCD, uppdatera `charts/todo/values-eks-ghcr.yaml:image.tag` i Git och pusha ändringen innan du trycker *Sync*. Då ser ArgoCD den nya versionen och rullar ut den automatiskt.

---

## 6. Troubleshooting

| Symptom | Possible cause | Resolution |
|---------|----------------|-----------|
| `ImagePullBackOff` on webapp | GHCR credentials missing or tag not pushed | Verify image exists (`docker manifest inspect ghcr.io/monswiklund/todo-app:latest`) and cluster can pull it (public repo or imagePullSecret) |
| MongoDB pod crash loops with FCV error | Reused old PVC with previous Mongo version | Delete release **and** PVC: `helm uninstall todo-app` → `kubectl delete pvc -n todo-app --all` before reinstall |
| LoadBalancer external IP is `<pending>` | Public subnets missing `kubernetes.io/role/elb = 1` tag | Re-apply tags on public subnets, then recreate service |
| Service reachable only inside VPC | Annotation `service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing` missing | Ensure values file contains the annotation for EKS deployments |
| Pods stuck in `Pending` with `CriticalAddonsOnly` taint warning | Only the system node pool is available | In EKS Auto Mode, set the `general-purpose` node pool min > 0 so workloads land on taint-free instances |
| Webapp logs `MONGO_URI environment variable is required` | ConfigMap not refreshed after updating the chart | Re-run `helm upgrade ... --reuse-values` or delete pods to pick up the ConfigMap that now exposes both `MONGO_URI` and `MONGO_CONNECTION_STRING` |
| ArgoCD refuses to apply job changes | Jobs are immutable | Our chart uses `Replace=true` on the init job; if you change it manually, delete the job before syncing |

---

## 7. Cleanup

```bash
# Remove the Helm release (keeps namespace unless `--namespace` flagged)
helm uninstall todo-app
kubectl delete namespace todo-app --wait=false

# (Optional) Remove ArgoCD application
kubectl delete -f argocd-app.yaml

# Delete cluster and VPC from AWS console (EKS → Delete cluster, VPC → Delete)
```

If you used Docker Desktop:

```bash
helm uninstall todo-app
kubectl delete namespace todo-app
```

---

## 8. Summary Checklist

- [ ] Build & push a multi-arch image with a unique tag (and note the tag).  
- [ ] Provision EKS cluster (Auto Mode), tag public subnets for ELB, ensure the `general-purpose` node pool has min ≥ 1.  
- [ ] `aws eks update-kubeconfig …`, confirm `kubectl config current-context` points to EKS, then run `kubectl get nodes`.  
- [ ] `helm upgrade --install todo-app charts/todo -f values-eks-ghcr.yaml --set image.tag=<your-tag>`.  
- [ ] Verify pods, services, and LoadBalancer DNS; `curl "http://<dns>/todos"` should return the seeded tasks.  
- [ ] (Optional) Register in ArgoCD for GitOps deployment.  
- [ ] Document results (screenshots of pods, services, and app UI) for the course report.

Lycka till med inlämningen! 🎉
