# ============================================================
# PROJECT 2 — VPC + EC2 + ALB + ASG + CloudWatch
# ============================================================
# Services:
#   VPC, Subnets, IGW, NAT GW, Route Tables
#   Security Groups, EC2, Launch Template
#   ALB, Target Group, Listener
#   ASG with scaling policies
#   CloudWatch Alarms (CPU scale out/in)
#   IAM Instance Profile (SSM access)
# ============================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────
variable "aws_region"    { default = "us-east-1" }
variable "project_name"  { default = "aws-learning-p2" }
variable "environment"   { default = "dev" }
variable "instance_type" { default = "t3.micro" }  # Free tier!

# Amazon Linux 2023 AMI (us-east-1) — auto latest
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-202*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────
# 1. VPC — Virtual Private Cloud (Our private network)
# ─────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"   # 65,536 IPs available
  enable_dns_hostnames = true             # EC2 ko hostname milega
  enable_dns_support   = true
  tags = merge(local.common_tags, { Name = "${var.project_name}-vpc" })
}

# ─────────────────────────────────────────────────────────────
# 2. SUBNETS
# Public  → ALB yahan hoga (internet se accessible)
# Private → EC2 yahan honge (internet se direct access NAHI)
# ─────────────────────────────────────────────────────────────

# PUBLIC SUBNETS (2 AZs for ALB — ALB ko 2 AZ chahiye!)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"   # 256 IPs
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true             # EC2 ko public IP milega
  tags = merge(local.common_tags, { Name = "${var.project_name}-public-1" })
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "${var.project_name}-public-2" })
}

# PRIVATE SUBNETS (EC2 instances yahan honge)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"
  tags = merge(local.common_tags, { Name = "${var.project_name}-private-1" })
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}b"
  tags = merge(local.common_tags, { Name = "${var.project_name}-private-2" })
}

# ─────────────────────────────────────────────────────────────
# 3. INTERNET GATEWAY — VPC ka door to internet
# ─────────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project_name}-igw" })
}

# ─────────────────────────────────────────────────────────────
# 4. NAT GATEWAY — Private subnet → Internet (one-way)
# EC2 (private) → NAT GW → Internet (npm install, updates)
# Internet → EC2 seedha nahi aa sakta!
# ─────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.project_name}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id   # NAT GW public subnet mein hota hai!
  tags          = merge(local.common_tags, { Name = "${var.project_name}-nat-gw" })
  depends_on    = [aws_internet_gateway.main]
}

# ─────────────────────────────────────────────────────────────
# 5. ROUTE TABLES
# Public RT  → IGW se internet access
# Private RT → NAT GW se internet access (outbound only)
# ─────────────────────────────────────────────────────────────

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"                  # Sab traffic
    gateway_id = aws_internet_gateway.main.id  # IGW se bahar
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-public-rt" })
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id  # NAT GW se bahar (one-way!)
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-private-rt" })
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# ─────────────────────────────────────────────────────────────
# 6. SECURITY GROUPS — Firewall rules
# ─────────────────────────────────────────────────────────────

# ALB Security Group — Internet se HTTP traffic allow
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: Allow HTTP from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Anyone can access port 80
  }

  egress {
    description = "All outbound allowed"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-alb-sg" })
}

# EC2 Security Group — Sirf ALB se traffic allow (direct internet NAHI!)
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "EC2: Allow traffic only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB only"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # SIRF ALB se!
  }

  egress {
    description = "All outbound (NAT GW se npm install, updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-ec2-sg" })
}

# ─────────────────────────────────────────────────────────────
# 7. IAM ROLE — EC2 ke liye (SSM + CloudWatch access)
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

# SSM Policy — SSH key ke bina EC2 mein ghusne ke liye!
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Policy — Metrics + Logs push karne ke liye
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile — Role ko EC2 se attach karne ka tarika
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ─────────────────────────────────────────────────────────────
# 8. LAUNCH TEMPLATE — EC2 ka blueprint (ASG use karta hai)
# ─────────────────────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # IAM Instance Profile — SSM + CloudWatch access
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  # Security Group
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # EBS Root Volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20    # 20 GB
      volume_type           = "gp3" # General Purpose SSD
      encrypted             = true  # Encrypted at rest
      delete_on_termination = true  # EC2 terminate → disk bhi delete
    }
  }

  # User Data — EC2 start hote waqt ye script chalti hai
  user_data = base64encode(file("${path.module}/../scripts/user-data.sh"))

  # Detailed monitoring — 1 min granularity (default 5 min)
  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, { Name = "${var.project_name}-ec2" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────
# 9. ALB — Application Load Balancer
# ─────────────────────────────────────────────────────────────
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false              # Internet-facing
  load_balancer_type = "application"      # L7 HTTP
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  enable_deletion_protection = false  # Learning ke liye off
  enable_http2               = true

  tags = merge(local.common_tags, { Name = "${var.project_name}-alb" })
}

# TARGET GROUP — EC2 instances ka group jahan ALB traffic bhejta hai
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 3000        # Node.js app ka port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Health Check — ALB ye endpoint hit karta hai
  # Agar 200 nahi aaya → EC2 unhealthy → traffic band!
  health_check {
    enabled             = true
    healthy_threshold   = 2      # 2 baar healthy → traffic bhejo
    unhealthy_threshold = 3      # 3 baar fail → traffic band
    timeout             = 5      # 5 sec mein response chahiye
    interval            = 30     # Har 30 sec mein check
    path                = "/health"
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-tg" })
}

# LISTENER — ALB pe port 80 sunna
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ─────────────────────────────────────────────────────────────
# 10. AUTO SCALING GROUP
# ─────────────────────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  min_size            = 1   # Minimum 1 EC2 hamesha
  max_size            = 4   # Maximum 4 EC2 tak scale kar sakta hai
  desired_capacity    = 2   # Normal time pe 2 EC2

  # Private subnets mein launch karo
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  # ALB Target Group se connect karo
  target_group_arns = [aws_lb_target_group.app.arn]

  # Launch Template use karo
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Health check type: ELB (ALB ka health check use karo)
  health_check_type         = "ELB"
  health_check_grace_period = 120  # New EC2 ko 2 min warmup time

  # Instance refresh — New launch template aane pe rolling update
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50  # Kam se kam 50% healthy raha karo
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ec2"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────
# 11. AUTO SCALING POLICIES + CLOUDWATCH ALARMS
# ─────────────────────────────────────────────────────────────

# SCALE OUT Policy — EC2 badhao jab CPU zyada ho
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1      # 1 EC2 badhao
  cooldown               = 180    # 3 min wait next scale tak
}

# SCALE IN Policy — EC2 hatao jab CPU kam ho
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1     # 1 EC2 hatao
  cooldown               = 300    # 5 min wait
}

# CloudWatch Alarm: CPU > 70% → Scale OUT trigger
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2          # 2 baar consecutive
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60         # Har 60 sec check
  statistic           = "Average"
  threshold           = 70         # 70% se zyada
  alarm_description   = "CPU > 70% — Scale Out!"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
  tags          = local.common_tags
}

# CloudWatch Alarm: CPU < 30% → Scale IN trigger
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5          # 5 baar consecutive (cautious!)
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30         # 30% se kam
  alarm_description   = "CPU < 30% — Scale In!"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
  tags          = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "alb_dns_name" {
  description = "ALB URL — site yahan live hogi!"
  value       = "http://${aws_lb.app.dns_name}"
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "asg_name" {
  description = "ASG name — AWS Console mein dekho"
  value       = aws_autoscaling_group.app.name
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}
