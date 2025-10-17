# Driftguide – C# Todo App på Kubernetes

Den här guiden sammanfattar hur du startar projektet lokalt och i ett Kubernetes-kluster, så att du kan verifiera funktionaliteten inför inlämningen.

## 1. Förutsättningar
- .NET 9 SDK installerad (`dotnet --version` ska visa 9.x).
- Åtkomst till en MongoDB-instans (Atlas eller egeninstallation).
- `kubectl` konfigurerad mot klustret där appen ska köras.
- `helm` installerat om du vill använda chart:et i `charts/todo/`.
- Ett namespace (t.ex. `todo-app`) med rättigheter att skapa resurser.

## 2. Konfigurera hemligheter

### Lokalt
Sätt anslutningssträngen innan du startar appen:
```bash
export MONGO_CONNECTION_STRING="mongodb+srv://<user>:<pass>@<cluster>/<db>?retryWrites=true&w=majority"
```

Alternativt: uppdatera `appsettings.json` med motsvarande värde. Kontrollera in att hemliga uppgifter inte versioneras.

### Kubernetes
Skapa hemligheten via CLI så du inte behöver checka in riktiga kredentialer:
```bash
kubectl create namespace todo-app

kubectl create secret generic mongo-credentials \
  --from-literal=MONGO_USER=<mongo-user> \
  --from-literal=MONGO_PASSWORD=<mongo-password> \
  --from-literal=MONGO_URI="mongodb://<mongo-user>:<mongo-password>@mongo:27017/todo?authSource=admin" \
  -n todo-app
```

> Tips: Om du använder Atlas, ersätt `MONGO_URI` med den publika connection stringen.

## 3. Lokal körning (utan Docker)
```bash
dotnet restore
dotnet run
```

Verifiera sedan:
```bash
curl http://localhost:5000/health
curl http://localhost:5000/todos
```

### Frontend
Öppna `http://localhost:5000` i webbläsaren – `wwwroot/index.html` använder API:t direkt.

## 4. Kubernetes med manifest (mappen `k8s/`)
1. Uppdatera `k8s/mongo-secret.yaml` om du vill skapa hemligheten från fil (rekommenderat är CLI enligt ovan).
2. Se över `k8s/mongo-pvc.yaml`: ange en `storageClassName` som finns i ditt kluster (t.ex. `gp2` i EKS, `standard` i GKE).
3. Deploya resurserna:
   ```bash
   kubectl apply -f k8s/
   ```
4. Kontrollera status:
   ```bash
   kubectl get pods -n todo-app
   kubectl get svc -n todo-app
   kubectl get ingress -n todo-app
   ```
5. Testa applikationen genom port-forward eller via ingress:
   ```bash
   kubectl port-forward svc/todo-service 8080:80 -n todo-app
   curl http://localhost:8080/health
   ```

## 5. Kubernetes med Helm (`charts/todo/`)
1. Anpassa `charts/todo/values.yaml`:
   - `image.repository` och `image.tag` till din build.
   - `env.secret.name` och `env.secret.key` om du bytt namn på hemligheten.
   - `ingress.host` till ett domännamn du kontrollerar.
2. Installera:
   ```bash
   helm install todo ./charts/todo -n todo-app \
     --set ingress.host=todo.example.com
   ```
3. För uppdateringar, kör `helm upgrade todo ./charts/todo -n todo-app`.

## 6. Förklara komponenterna (underlag för inlämningen)
- **Todo Deployment (`k8s/todo-deployment.yaml`)** – kör REST-API:t i tre repliker, pekar mot MongoDB och exponerar port 8080.
- **Todo Service (`k8s/todo-service.yaml`)** – intern load balancer som gör Deploymenten tillgänglig via port 80 i klustret.
- **Ingress (`k8s/ingress.yaml`)** – routar HTTP-trafik från `todo.local` (justera host) mot tjänsten.
- **Mongo StatefulSet + PVC (`k8s/mongo-statefulset.yaml`/`mongo-pvc.yaml`)** – permanenta lagringsvolymer och MongoDB-exemplar.
- **Secret (`k8s/mongo-secret.yaml`)** – innehåller anslutningsuppgifterna som injiceras i både backend och databasen.

Det här avsnittet kan du använda för att skriva svaren på uppgiftens teoridel om komponenternas roller och funktioner.

## 7. Validering efter deploy
- `kubectl logs deploy/todo-app -n todo-app` – verifiera att API:t lyckas ansluta till MongoDB.
- `kubectl exec sts/mongo -n todo-app -- mongo --eval 'db.runCommand({ ping: 1 })'` – kontrollera databasen.
- `curl http://<ingress-host>/todos` – testa datapathen via ingress.

## 8. Rensning
Vid behov:
```bash
kubectl delete -f k8s/
# eller
helm uninstall todo -n todo-app
kubectl delete namespace todo-app
```

---

Nu har du både körinstruktioner och en struktur för att beskriva vad som händer i klustret – använd dessa noteringar när du skriver ditt inlämningssvar.
