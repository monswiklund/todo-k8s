terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"  # Senaste version för multi-region stöd
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Grundläggande nätverk, behöver egen VPC för kontroll över säkerhet
resource "aws_vpc" "todo_vpc" {
  cidr_block           = "10.0.0.0/16"  # Ger utrymme för ~65k IP-adresser
  enable_dns_hostnames = true           # Krävs för AWS services att fungera
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
  cidr_block              = "10.0.1.0/24"  # 251 användbara IPs
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true  # Auto-assignar publika IPs

  tags = {
    Name = "todo-public-1"
  }
}

resource "aws_subnet" "todo_public_2" {
  vpc_id                  = aws_vpc.todo_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"  # Annan AZ för redundans
  map_public_ip_on_launch = true

  tags = {
    Name = "todo-public-2"
  }
}

# Route table, säger åt trafik hur den ska komma ut till internet
resource "aws_route_table" "todo_public_rt" {
  vpc_id = aws_vpc.todo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"  # All trafik som inte är lokal
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
  name = "todo-swarm-"
  vpc_id      = aws_vpc.todo_vpc.id

  # SSH-regler hanteras via separata security group rules för flexibilitet

  # Port 8080 från internet för direkt åtkomst (fallback)
  ingress {
    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Docker Swarm portar, bara mellan mina egna instances
  # Port 2377: Manager kommunikation
  ingress {
    from_port = 2377
    to_port   = 2377
    protocol  = "tcp"
    self      = true  # Bara från andra i samma security group
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
    protocol  = "udp"  # Både TCP och UDP behövs
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
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // För github Actions, Kollade på SSM men krånglade och fastnae så här får duga
    description = "SSH from internet to bastion host"
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
  public_key = file("~/.ssh/id_rsa.pub")  # Förutsätter att jag har SSH-nyckel lokalt
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

# Attach DynamoDB policy to EC2 role
resource "aws_iam_role_policy_attachment" "ec2_dynamodb_policy_attachment" {
  role       = aws_iam_role.ec2_dynamodb_role.name
  policy_arn = aws_iam_policy.todo_minimal_policy.arn
}

# Instance profile, kopplar IAM role till EC2 instances
resource "aws_iam_instance_profile" "ec2_dynamodb_profile" {
  name = "ec2-dynamodb-profile"
  role = aws_iam_role.ec2_dynamodb_role.name
}


# Manager node
resource "aws_instance" "swarm_manager" {
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.instance_type
  key_name                = aws_key_pair.todo_key.key_name
  vpc_security_group_ids  = [aws_security_group.todo_swarm_sg.id]
  subnet_id               = aws_subnet.todo_public_1.id
  iam_instance_profile    = aws_iam_instance_profile.ec2_dynamodb_profile.name  # För DynamoDB access

  # Installera Docker och Docker Compose automatiskt vid boot
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user  # Låter ec2-user köra Docker utan sudo

    # Docker Compose för stack management
    curl -L "https://github.com/docker/compose/releases/download/v2.39.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  EOF

  tags = {
    Name = "swarm-manager"
    Role = "manager"
  }
}



# Worker nodes
resource "aws_instance" "swarm_workers" {
  count = 3
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.instance_type
  key_name                = aws_key_pair.todo_key.key_name
  vpc_security_group_ids  = [aws_security_group.todo_swarm_sg.id]
  subnet_id = count.index % 2 == 0 ? aws_subnet.todo_public_1.id : aws_subnet.todo_public_2.id
  # Round-robin över båda AZ:s
  iam_instance_profile    = aws_iam_instance_profile.ec2_dynamodb_profile.name

  # Workers behöver bara Docker, inte Compose
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
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

  enable_deletion_protection = false  # För development

  tags = {
    Name = "todo-swarm-alb"
  }
}

# Target Group för manager node
resource "aws_lb_target_group" "todo_manager_tg" {
  name     = "todo-manager-tg"
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
    Name = "todo-manager-tg"
  }
}

# Target Group Attachment för manager
resource "aws_lb_target_group_attachment" "manager_attachment" {
  target_group_arn = aws_lb_target_group.todo_manager_tg.arn
  target_id        = aws_instance.swarm_manager.id
  port             = 8080
}

# ALB Listener för HTTP traffic
resource "aws_lb_listener" "todo_listener" {
  load_balancer_arn = aws_lb.todo_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.todo_manager_tg.arn
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

# SSH Access Rules - Separata för flexibilitet och säkerhet
resource "aws_security_group_rule" "admin_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks = [var.admin_ip_cidr]
  security_group_id = aws_security_group.todo_swarm_sg.id
  description       = "SSH access for admin"
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


