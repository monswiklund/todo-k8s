# Todo App

- ASP.NET Core minimal API + MongoDB.
- Helm-chart finns i `charts/todo/`.
- Deploy körs i EKS Auto Mode via ArgoCD.
- GitHub Actions pushar ny container automatiskt.

## Snabb test lokalt
```
dotnet restore
export MONGO_CONNECTION_STRING="mongodb://localhost:27017/todo-app"
dotnet run
```

För detaljer kring moln-deployment: se `docs/DEPLOYMENT_GUIDE.md`.
