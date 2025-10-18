# Todo App (ASP.NET Core + MongoDB + Kubernetes)

Det här projektet innehåller en minimal ASP.NET Core API-applikation som pratar med MongoDB och är paketerad som ett Helm-diagram för Kubernetes. Miljön körs lokalt med Docker Desktop och i molnet på Amazon EKS Auto Mode med ArgoCD som GitOps-motor.

## Snabbstart lokalt
```bash
dotnet restore
export MONGO_CONNECTION_STRING="mongodb://localhost:27017/todo-app"
dotnet run
curl http://localhost:5000/health
```
Applikationen läser anslutningen från `MONGO_URI`, `MONGO_CONNECTION_STRING` eller `Mongo:ConnectionString` i `appsettings.json`. Alla Mongo-tjänster (`IMongoClient`, `IMongoDatabase`, `IMongoCollection<TodoTask>`) registreras i `Program.cs`, och API:et exponerar CRUD-endpoints under `/todos` samt statiska filer i `wwwroot/`.

## Deployment i Kubernetes (översikt)
1. Bygg multi-arch-container och pusha till GHCR:  
   `docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/monswiklund/todo-app:<tag> --push .`
2. Uppdatera `charts/todo/values-eks-ghcr.yaml:image.tag` (workflowet gör detta automatiskt vid merge till `main`).
3. Deploya med Helm:  
   `helm upgrade --install todo-app charts/todo -f charts/todo/values-eks-ghcr.yaml`
4. Validera: `kubectl get pods -n todo-app` och `curl "http://<load-balancer-dns>/todos"`.
5. ArgoCD auto-syncar commits i `main` och håller klustret i synk. Manifestet finns i `argocd-app.yaml`.

Detaljerade instruktioner och kursrapport finns i `docs/` (se nedan).

## CI/CD
GitHub Actions-workflowen `.github/workflows/build-and-release.yaml`:
- Kör `dotnet build/test` på alla PRs.
- Bygger och pushar multi-arch Docker-image vid push till `main`.
- Uppdaterar `charts/todo/values-eks-ghcr.yaml` och `argocd-app.yaml` med samma bildtagg.
- Commits signerade `[skip ci]` förhindrar loopar. ArgoCD plockar upp ändringen och rullar ut automatiskt.

## Strukturell översikt
- `Program.cs`, `Models/`, `Services/` – applikationskod.
- `wwwroot/` – statiska resurser (bl.a. `index.html`).
- `charts/todo/` – Helm-diagrammet för MongoDB + webbapp.
- `docs/`  
  - `DEPLOYMENT_GUIDE.md` – full körinstruktion för EKS Auto Mode, Helm och ArgoCD.  
  - `REPORT.md` – sammanfattning som besvarar kursuppgiften.
- `terraform/` – historisk referenskonfiguration (kommenterad) för ett manuellt EKS-kluster.

## Nästa steg
- Följ `docs/DEPLOYMENT_GUIDE.md` för steg-för-steg-guidning i molnet.
- Använd `docs/REPORT.md` som underlag till kursinlämningen.
- Uppdatera applikationen (t.ex. `wwwroot/index.html`) och låt Actions + ArgoCD sköta releasen.
