terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # Senaste version för multi-region stöd
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Grundläggande nätverk, behöver egen VPC för kontroll över säkerhet
resource "aws_vpc" "todo_vpc" {
  cidr_block = "10.0.0.0/16" # Ger utrymme för ~65k IP-adresser
  enable_dns_hostnames = true          # Krävs för AWS services att fungera
  enable_dns_support   = true

  tags = {
    Name = "todo-swarm-vpc"
  }
}

# Internet Gateway, så mina EC2 kan nå internet
resource "aws_internet_gateway" "todo_igw" {
  vpc_id = aws_vpc.todo_vpc.id

  tags = {
    Name = "todo-swarm-igw"
  }
}

# Två subnets för hög tillgänglighet, om en AZ går ner finns backup
resource "aws_subnet" "todo_public_1" {
  vpc_id                  = aws_vpc.todo_vpc.id
  cidr_block = "10.0.1.0/24" # 251 användbara IPs
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true # Auto-assignar publika IPs

  tags = {
    Name = "todo-public-1"
  }
}

resource "aws_subnet" "todo_public_2" {
  vpc_id                  = aws_vpc.todo_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b" # Annan AZ för redundans
  map_public_ip_on_launch = true

  tags = {
    Name = "todo-public-2"
  }
}

# Route table, säger åt trafik hur den ska komma ut till internet
resource "aws_route_table" "todo_public_rt" {
  vpc_id = aws_vpc.todo_vpc.id

  route {
    cidr_block = "0.0.0.0/0" # All trafik som inte är lokal
    gateway_id = aws_internet_gateway.todo_igw.id
  }

  tags = {
    Name = "todo-public-rt"
  }
}

# Koppla route table till båda subnets
resource "aws_route_table_association" "todo_public_1_rta" {
  subnet_id      = aws_subnet.todo_public_1.id
  route_table_id = aws_route_table.todo_public_rt.id
}

resource "aws_route_table_association" "todo_public_2_rta" {
  subnet_id      = aws_subnet.todo_public_2.id
  route_table_id = aws_route_table.todo_public_rt.id
}


# EC2 Security Group, fungerar som brandvägg
resource "aws_security_group" "todo_swarm_sg" {
  name   = "todo-swarm-"
  vpc_id = aws_vpc.todo_vpc.id

  # SSH-regler hanteras via separata security group rules för flexibilitet

  # Docker Swarm portar, bara mellan mina egna instances
  # Port 2377: Manager kommunikation
  ingress {
    from_port = 2377
    to_port   = 2377
    protocol  = "tcp"
    self = true # Bara från andra i samma security group
  }

  # Port 7946: Node discovery och communication
  ingress {
    from_port = 7946
    to_port   = 7946
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 7946
    to_port   = 7946
    protocol = "udp" # Både TCP och UDP behövs
    self      = true
  }

  # Port 4789: Overlay network trafik mellan containers
  ingress {
    from_port = 4789
    to_port   = 4789
    protocol  = "udp"
    self      = true
  }

  # Specifik utgående trafik för säkerhet
  # HTTPS för paketuppdateringar och Docker Hub
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP för paketuppdateringar (yum)
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DNS resolution
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Docker Swarm egress rules - behövs för noder att kommunicera med varandra
  # Port 2377: Manager kommunikation
  egress {
    from_port = 2377
    to_port   = 2377
    protocol  = "tcp"
    self      = true
  }

  # Port 7946: Node discovery och communication
  egress {
    from_port = 7946
    to_port   = 7946
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port = 7946
    to_port   = 7946
    protocol  = "udp"
    self      = true
  }

  # Port 4789: Overlay network trafik mellan containers
  egress {
    from_port = 4789
    to_port   = 4789
    protocol  = "udp"
    self      = true
  }

  tags = {
    Name = "todo-swarm-sg"
  }
}

# Application Load Balancer Security Group
resource "aws_security_group" "alb_sg" {
  name   = "todo-alb-sg"
  vpc_id = aws_vpc.todo_vpc.id

  # HTTP från internet
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS från internet (för framtida SSL)
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Standard egress - tillåt all utgående trafik
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "todo-alb-sg"
  }
}


# Bastion Host Security Group
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH to bastion host"
  vpc_id      = aws_vpc.todo_vpc.id

  # SSH från internet till bastion
  # NOTE: 0.0.0.0/0 används för GitHub Actions CI/CD access
  # ALTERNATIV SOM ÖVERVÄGDES:
  # - AWS Systems Manager Session Manager (eliminerar SSH helt, men krånglade med setup)
  # - GitHub-hosted runners self-hosted i VPC (för komplex för projektstorlek)
  # - VPN-lösning (onödigt för utvecklingsmiljö)
  # SÄKERHET: fail2ban + SSH key-only auth + härdad sshd_config används
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH from internet for GitHub Actions CI/CD"
  }

  # Standard egress - tillåt all utgående trafik
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# SSH key så jag kan logga in på mina EC2 instances
resource "aws_key_pair" "todo_key" {
  key_name   = "todo-swarm-key"
  public_key = file("~/.ssh/id_rsa.pub") # Förutsätter att jag har SSH-nyckel lokalt
}

# senaste Amazon Linux 2023 AMI 
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# IAM setup för säker AWS-åtkomst, bättre än hardkodade keys
resource "aws_iam_role" "ec2_dynamodb_role" {
  name = "ec2-dynamodb-role"

  # Trust policy, låter EC2 "anta" denna roll
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "ec2-dynamodb-role"
  }
}

# Ge rollen behörighet till DynamoDB
resource "aws_iam_policy" "todo_minimal_policy" {
  name        = "todo-dynamodb-minimal"
  description = "Minimal permissions for TodoApp Tasks table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/Tasks"
      }
    ]
  })
}

# SSM Parameter Store policy för Docker Swarm token management
resource "aws_iam_policy" "swarm_ssm_policy" {
  name        = "swarm-ssm-tokens"
  description = "Allow EC2 instances to read/write swarm tokens in SSM Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/swarm/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach DynamoDB policy to EC2 role
resource "aws_iam_role_policy_attachment" "ec2_dynamodb_policy_attachment" {
  role       = aws_iam_role.ec2_dynamodb_role.name
  policy_arn = aws_iam_policy.todo_minimal_policy.arn
}

# Attach SSM policy to EC2 role
resource "aws_iam_role_policy_attachment" "ec2_ssm_policy_attachment" {
  role       = aws_iam_role.ec2_dynamodb_role.name
  policy_arn = aws_iam_policy.swarm_ssm_policy.arn
}

# Instance profile, kopplar IAM role till EC2 instances
resource "aws_iam_instance_profile" "ec2_dynamodb_profile" {
  name = "ec2-dynamodb-profile"
  role = aws_iam_role.ec2_dynamodb_role.name
}


# Manager node
resource "aws_instance" "swarm_manager" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.todo_key.key_name
  vpc_security_group_ids = [aws_security_group.todo_swarm_sg.id]
  subnet_id            = aws_subnet.todo_public_1.id
  iam_instance_profile = aws_iam_instance_profile.ec2_dynamodb_profile.name # För DynamoDB access

  # Installera Docker och Docker Compose automatiskt vid boot
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Logging
    exec > >(tee /var/log/user-data.log)
    exec 2>&1
    echo "=== Manager Node Initialization Started at $(date) ==="

    # Install Docker
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user

    # Docker Compose för stack management
    curl -L "https://github.com/docker/compose/releases/download/v2.39.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Wait for Docker to be ready
    echo "Waiting for Docker to be ready..."
    timeout=60
    while ! docker info >/dev/null 2>&1; do
      sleep 2
      timeout=$((timeout-2))
      if [ $timeout -le 0 ]; then
        echo "ERROR: Docker failed to start"
        exit 1
      fi
    done
    echo "Docker is ready"

    # Initialize Docker Swarm
    echo "Initializing Docker Swarm..."
    PRIVATE_IP=$(hostname -I | awk '{print $1}')

    # Check if already in swarm and is manager
    if docker node ls >/dev/null 2>&1; then
      echo "Already initialized as swarm manager"
    else
      echo "Leaving any existing swarm state..."
      docker swarm leave --force 2>/dev/null || true

      echo "Initializing new swarm..."
      docker swarm init --advertise-addr $PRIVATE_IP
      echo "Swarm initialized successfully"
    fi

    # Generate and store worker token in SSM Parameter Store
    echo "Storing worker token in SSM Parameter Store..."
    WORKER_TOKEN=$(docker swarm join-token worker -q)
    MANAGER_IP=$(docker info --format '{{.Swarm.NodeAddr}}')

    aws ssm put-parameter \
      --name "/swarm/worker-token" \
      --value "$WORKER_TOKEN" \
      --type "SecureString" \
      --overwrite \
      --region ${var.aws_region}

    aws ssm put-parameter \
      --name "/swarm/manager-ip" \
      --value "$MANAGER_IP" \
      --type "String" \
      --overwrite \
      --region ${var.aws_region}

    # Deploy TodoApp stack automatically
    echo "Deploying TodoApp stack..."

    # Create docker-compose.yml
    cat > /home/ec2-user/docker-compose.yml << 'COMPOSE_EOF'
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
      - ASPNETCORE_URLS=http://+:8080

    deploy:
      replicas: 3

      # Placement constraints - endast köra på worker nodes
      placement:
        constraints:
          - node.role == worker

      # Update strategy
      update_config:
        parallelism: 1
        delay: 10s
        failure_action: rollback
        monitor: 60s
        max_failure_ratio: 0.3

      # Rollback configuration
      rollback_config:
        parallelism: 1
        delay: 5s
        failure_action: pause
        monitor: 60s

      # Restart policy
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s

      # Resource limits
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M

    # Health check
    healthcheck:
      test: [ "CMD-SHELL", "curl -f http://localhost:8080/health || exit 1" ]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

    networks:
      - todo-network

networks:
  todo-network:
    driver: overlay
    attachable: true
    driver_opts:
      encrypted: "true"
COMPOSE_EOF

    chown ec2-user:ec2-user /home/ec2-user/docker-compose.yml

    # Wait for workers to join (max 10 minutes)
    echo "Waiting for workers to join swarm..."
    for i in {1..60}; do
      WORKER_COUNT=$(docker node ls --filter "role=worker" -q | wc -l)
      echo "Workers joined: $WORKER_COUNT/3"

      if [ "$WORKER_COUNT" -ge 3 ]; then
        echo "All workers have joined!"
        break
      fi

      sleep 10
    done

    # Deploy stack
    echo "Deploying stack to swarm..."
    docker stack deploy -c /home/ec2-user/docker-compose.yml todoapp

    echo "Stack deployed! Checking status..."
    sleep 10
    docker stack ps todoapp

    echo "=== Manager Node Initialization Completed at $(date) ==="
  EOF

  tags = {
    Name = "swarm-manager"
    Role = "manager"
  }
}



# Worker nodes
resource "aws_instance" "swarm_workers" {
  count         = 3
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.todo_key.key_name
  vpc_security_group_ids = [aws_security_group.todo_swarm_sg.id]
  subnet_id = count.index % 2 == 0 ? aws_subnet.todo_public_1.id : aws_subnet.todo_public_2.id
  # Round-robin över båda AZ:s
  iam_instance_profile = aws_iam_instance_profile.ec2_dynamodb_profile.name

  # Workers behöver bara Docker, inte Compose
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Logging
    exec > >(tee /var/log/user-data.log)
    exec 2>&1
    echo "=== Worker Node Initialization Started at $(date) ==="

    # Install Docker
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user

    # Wait for Docker to be ready
    echo "Waiting for Docker to be ready..."
    timeout=60
    while ! docker info >/dev/null 2>&1; do
      sleep 2
      timeout=$((timeout-2))
      if [ $timeout -le 0 ]; then
        echo "ERROR: Docker failed to start"
        exit 1
      fi
    done
    echo "Docker is ready"

    # Wait for manager to store token in SSM (max 5 minutes)
    echo "Waiting for manager to store token in SSM..."
    max_attempts=60
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if aws ssm get-parameter --name "/swarm/worker-token" --region ${var.aws_region} --with-decryption >/dev/null 2>&1; then
        echo "Token found in SSM"
        break
      fi
      echo "Waiting for token... (attempt $((attempt+1))/$max_attempts)"
      sleep 5
      attempt=$((attempt+1))
    done

    if [ $attempt -eq $max_attempts ]; then
      echo "ERROR: Timeout waiting for swarm token"
      exit 1
    fi

    # Retrieve token and manager IP from SSM
    echo "Retrieving swarm token and manager IP from SSM..."
    WORKER_TOKEN=$(aws ssm get-parameter \
      --name "/swarm/worker-token" \
      --region ${var.aws_region} \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text)

    MANAGER_IP=$(aws ssm get-parameter \
      --name "/swarm/manager-ip" \
      --region ${var.aws_region} \
      --query 'Parameter.Value' \
      --output text)

    echo "Manager IP: $MANAGER_IP"

    # Join the swarm
    echo "Joining Docker Swarm..."
    max_join_attempts=10
    join_attempt=0
    while [ $join_attempt -lt $max_join_attempts ]; do
      if docker swarm join --token "$WORKER_TOKEN" "$MANAGER_IP:2377" 2>&1; then
        echo "Successfully joined swarm"
        break
      fi
      echo "Join attempt failed, retrying... ($((join_attempt+1))/$max_join_attempts)"
      sleep 10
      join_attempt=$((join_attempt+1))
    done

    if [ $join_attempt -eq $max_join_attempts ]; then
      echo "ERROR: Failed to join swarm after $max_join_attempts attempts"
      exit 1
    fi

    echo "=== Worker Node Initialization Completed at $(date) ==="
  EOF

  tags = {
    Name = "swarm-worker-${count.index + 1}"
    Role = "worker"
  }
}

# Application Load Balancer
resource "aws_lb" "todo_alb" {
  name               = "todo-swarm-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_sg.id]
  subnets = [aws_subnet.todo_public_1.id, aws_subnet.todo_public_2.id]

  enable_deletion_protection = false # För development

  tags = {
    Name = "todo-swarm-alb"
  }
}

# Target Group för worker nodes (BEST PRACTICE: Manager endast för fördelning)
# Swarm routing mesh distribuerar trafik till containers som körs på workers
resource "aws_lb_target_group" "todo_workers_tg" {
  name = "todo-workers-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.todo_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "8080"
    protocol            = "HTTP"
  }

  tags = {
    Name = "todo-workers-tg"
  }
}

# Target Group Attachments för alla worker nodes
resource "aws_lb_target_group_attachment" "worker_attachments" {
  count            = 3
  target_group_arn = aws_lb_target_group.todo_workers_tg.arn
  target_id        = aws_instance.swarm_workers[count.index].id
  port             = 8080
}

# ALB Listener för HTTP traffic
resource "aws_lb_listener" "todo_listener" {
  load_balancer_arn = aws_lb.todo_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.todo_workers_tg.arn
  }
}

# Separata Security Group Rules för att undvika cirkulära referenser
resource "aws_security_group_rule" "alb_to_ec2_app" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.todo_swarm_sg.id
}

resource "aws_security_group_rule" "alb_to_ec2_health" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.todo_swarm_sg.id
}

# Bastion Host Instance
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.todo_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  subnet_id = aws_subnet.todo_public_1.id

  # Minimal user data för bastion hårdning
  user_data = <<-EOF
    #!/bin/bash
    yum update -y

    # Stärka SSH konfiguration
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
    echo "PubkeyAcceptedKeyTypes +ssh-ed25519" >> /etc/ssh/sshd_config
    systemctl restart sshd

    # Installera fail2ban för brute-force skydd
    yum install -y epel-release
    yum install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
  EOF

  tags = {
    Name = "bastion-host"
    Role = "bastion"
  }
}

# Elastic IP för bastion (stabil publik adress)
resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = {
    Name = "bastion-eip"
  }
}

# Uppdatera Swarm SG: SSH endast från bastion
resource "aws_security_group_rule" "swarm_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion_sg.id
  security_group_id        = aws_security_group.todo_swarm_sg.id
  description              = "SSH from bastion host only"
}


