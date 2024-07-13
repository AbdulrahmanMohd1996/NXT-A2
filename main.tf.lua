provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "main-vpc"
  }
}

# Subnets
resource "aws_subnet" "frontend" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.frontend_subnet_cidr
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "frontend-subnet"
  }
}

resource "aws_subnet" "backend" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.backend_subnet_cidr
  availability_zone = "us-west-2a"
  tags = {
    Name = "backend-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.frontend.id
  tags = {
    Name = "main-nat-gateway"
  }
}

resource "aws_eip" "nat" {
  vpc = true
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "frontend" {
  subnet_id      = aws_subnet.frontend.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "backend" {
  subnet_id      = aws_subnet.backend.id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "frontend_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "frontend-sg"
  }
}

resource "aws_security_group" "backend_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg"
  }
}

# Instances
resource "aws_instance" "frontend1" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.frontend.id
  security_groups = [aws_security_group.frontend_sg.name]
  tags = {
    Name = "frontend1"
  }
}

resource "aws_instance" "frontend2" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.frontend.id
  security_groups = [aws_security_group.frontend_sg.name]
  tags = {
    Name = "frontend2"
  }
}

resource "aws_instance" "backend1" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.backend.id
  security_groups = [aws_security_group.backend_sg.name]
  tags = {
    Name = "backend1"
  }
}

resource "aws_instance" "backend2" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.backend.id
  security_groups = [aws_security_group.backend_sg.name]
  tags = {
    Name = "backend2"
  }
}

# Load Balancers
resource "aws_elb" "frontend_elb" {
  name               = "frontend-elb"
  availability_zones = ["us-west-2a"]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  instances = [
    aws_instance.frontend1.id,
    aws_instance.frontend2.id
  ]

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "frontend-elb"
  }
}

resource "aws_elb" "backend_elb" {
  name               = "backend-elb"
  availability_zones = ["us-west-2a"]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  instances = [
    aws_instance.backend1.id,
    aws_instance.backend2.id
  ]

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "backend-elb"
  }
}

# RDS Instance
resource "aws_rds_instance" "main" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  instance_class       = "db.t2.micro"
  name                 = "mydb"
  username             = "admin"
  password             = "password"
  db_subnet_group_name = aws_db_subnet_group.main.name

  vpc_security_group_ids = [aws_security_group.backend_sg.id]

  tags = {
    Name = "main-rds"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "main-subnet-group"
  subnet_ids = [aws_subnet.backend.id]

  tags = {
    Name = "main-subnet-group"
  }
}

# ElastiCache Cluster
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "my-redis"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"

  subnet_group_name = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.backend_sg.id]

  tags = {
    Name = "main-redis"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "main-subnet-group"
  subnet_ids = [aws_subnet.backend.id]

  tags = {
    Name = "main-subnet-group"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "main" {
  bucket = "my-app-bucket"

  tags = {
    Name = "main-s3"
  }
}

# WAF
resource "aws_waf_web_acl" "main" {
  name        = "main-web-acl"
  metric_name = "mainWebAcl"

  default_action {
    type = "ALLOW"
  }

  rule {
    action {
      type = "BLOCK"
    }

    priority = 1
    rule_id  = aws_waf_rule.main.id
  }
}

resource "aws_waf_rule" "main" {
  name        = "main-rule"
  metric_name = "mainRule"

  predicates {
    data_id = aws_waf_byte_match_set.main.id
    negated = false
    type    = "ByteMatch"
  }
}

resource "aws_waf_byte_match_set" "main" {
  name = "main-byte-match-set"
  byte_match_tuples {
    field_to_match {
      type = "HEADER"
      data = "User-Agent"
    }

    positional_constraint = "CONTAINS"
    target_string         = "BadBot"
    text_transformation   = "NONE"
  }
}
