# TODO App Deployment

## Första gången

### 1. Infrastruktur
```bash
[LOKALT]
terraform apply
```

### 2. Setup Swarm
```bash
[LOKALT] 
ssh -i ~/.ssh/id_rsa ec2-user@<MANAGER_IP>

[MANAGER]
docker swarm init --advertise-addr <PRIVAT_IP>
# Kopiera token som skapas

[WORKER] - SSH till varje worker och kör:
docker swarm join --token <TOKEN> <MANAGER_IP>:2377
```

### 3. Deploya app
```bash
[MANAGER]
mkdir -p ~/todo-app && cd ~/todo-app

cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  todoapp:
    image: codecrasher2/todoapp:latest
    ports:
      - "8080:8080"
    dns:
      - 8.8.8.8
      - 8.8.4.4
    environment:
      - AWS_REGION=eu-west-1
      - ASPNETCORE_ENVIRONMENT=Development
    deploy:
      replicas: 3
    networks:
      - todo-network

networks:
  todo-network:
    driver: overlay
EOF

docker stack deploy -c docker-compose.yml todoapp
```

## Uppdateringar

### 1. Bygg ny image
```bash
[LOKALT]
docker buildx build --platform linux/amd64,linux/arm64 -t codecrasher2/todoapp:latest --push .
```

### 2. Uppdatera service
```bash
[MANAGER]  
docker service update --image codecrasher2/todoapp:latest todoapp_todoapp
```

## Kontrollera status
```bash
[MANAGER]
docker node ls           # Se alla noder
docker service ls        # Se services  
docker service ps todoapp_todoapp  # Se replicas
```