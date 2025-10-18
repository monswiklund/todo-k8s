# Documentation

- `DEPLOYMENT_GUIDE.md` – komplett guide för att köra applikationen lokalt och i Amazon EKS Auto Mode med Helm och ArgoCD. Innehåller felsökningstips och checklistor.
- `REPORT.md` – sammanfattar kursuppgiften: arkitektur, Kubernetes-manifest, säkerhetslösning och deployprocess.

Historiska Terraformfiler finns kvar i `terraform/` som referens, men GitOps-flödet bygger på Helm + ArgoCD. Inga rå K8s-manifest (`k8s/`) behövs längre – Helm-diagrammet är källan till sanning.***
