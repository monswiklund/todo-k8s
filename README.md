# C# Todo App – MongoDB & Kubernetes

Det här projektet har moderniserats från DynamoDB till MongoDB och försetts med en komplett Kubernetes-distribution (manifests + Helm-chart) som fungerar både lokalt och i EKS. Dokumentet sammanfattar vad som gjorts och hur du kör allt.

## Vad som är gjort
- **Databasbyte:** All DynamoDB-användning har ersatts med MongoDB (`MongoDB.Driver`). `TaskService` använder `IMongoCollection<TodoTask>` och `Program.cs` injicerar klient, databas och hälsokontroll mot Mongo.
- **Konfiguration:** Applikationen läser anslutningssträngen från miljövariabeln `MONGO_CONNECTION_STRING` eller `Mongo:ConnectionString` i `appsettings.json`. En lokal mall finns i `appsettings.json` (git-ignoread).
- **Docker Compose:** Uppdaterad så Todo-appen får `MONGO_CONNECTION_STRING`. Lägg till egen MongoDB-tjänst eller peka mot Atlas.
- **Kubernetes-manifests (`k8s/`):** Namespace `todo-app`, Deployment (3 repliker), Service, Ingress, StatefulSet + PVC för Mongo samt Secret som bär anslutningsuppgifterna.
- **Helm-chart (`charts/todo/`):** Speglar samma konfiguration och underlättar GitOps-baserad distribution.
- **GitOps-exempel:** README innehåller en Argo CD Application-definition för både rena manifests och Helm.

## Kör lokalt
1. Installera .NET 9 SDK och en MongoDB-instans (t.ex. Docker eller Atlas).  
2. Sätt anslutningssträngen (exempel med platshållare för Atlas):
   ```bash
   export MONGO_CONNECTION_STRING="mongodb+srv://<mongo-user>:<mongo-password>@cluster0.example.mongodb.net/todo-app?retryWrites=true&w=majority"
   ```
   eller ändra `appsettings.json`:
   ```json
   {
     "Mongo": {
       "ConnectionString": "mongodb+srv://<mongo-user>:<mongo-password>@cluster0.example.mongodb.net/todo-app"
     }
   }
   ```
3. Kör appen:
   ```bash
   dotnet run
   ```
4. Verifiera:
   ```bash
   curl http://localhost:5000/health
   curl http://localhost:5000/todos
   ```

## Docker Compose
`docker-compose.yml` injicerar rätt miljövariabler. Lägg till en MongoDB-tjänst eller peka mot extern instans, exempel:
```bash
MONGO_CONNECTION_STRING="mongodb://<mongo-user>:<mongo-password>@mongo:27017/todo-app?authSource=admin" docker compose up
```

## Kubernetes-manifests
```bash
kubectl create namespace todo-app
kubectl apply -f k8s/
```
Skapa hemligheten med dina riktiga uppgifter innan du deployar, exempel:
```bash
kubectl create secret generic mongo-credentials \
  --from-literal=MONGO_USER=<mongo-user> \
  --from-literal=MONGO_PASSWORD=<mongo-password> \
  --from-literal=MONGO_URI="mongodb+srv://<mongo-user>:<mongo-password>@cluster0.example.mongodb.net/todo-app?retryWrites=true&w=majority" \
  -n todo-app
```
Port-forward för test:
```bash
kubectl port-forward svc/todo-service 8080:80 -n todo-app
curl http://localhost:8080/todos
```

## Helm-installation
```bash
kubectl create namespace todo-app
helm install todo ./charts/todo -n todo-app \
  --set image.repository=ghcr.io/monswiklund/todo-app \
  --set image.tag=latest \
  --set ingress.host=todo.example.com \
  --set env.secret.name=mongo-credentials
```
Override-filer och fler värden finns i `charts/todo/values.yaml`.

## GitOps med Argo CD
Manifests:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: todo-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: main
    path: kub8/k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: todo-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
För Helm ändra `spec.source.path` till `kub8/charts/todo` och lägg till `helm.values` efter behov.

## Nästa steg
- Sätt upp DNS för `todo.<domain>` och peka mot ingressens IP/ALB.
- Bygg och pusha en produktionsimage (`docker build` + registry).
- Städa bort den deployment-variant (rå manifests eller Helm) du inte tänker använda långsiktigt.
# k8-test
