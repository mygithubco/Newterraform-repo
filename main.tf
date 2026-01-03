#########################################
# AWS Provider
#########################################
provider "aws" {
  region = "ap-southeast-1"
}

terraform {
  backend "s3" {
    bucket         = "my-terraform-backend-jenkins"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
}

#########################################
# Get Default VPC & Subnets
#########################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#########################################
# Key Pair
#########################################
resource "aws_key_pair" "app001-key-r" {
  key_name   = "app001-key"
  public_key = file("${path.module}/id_rsa.pub")
}

#########################################
# Security Group
#########################################
resource "aws_security_group" "allow_all" {
  name        = "allow_all_traffic"
  description = "Allow all inbound and outbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#########################################
# Server Count
#########################################
variable "server_count" {
  default = 1
}

#########################################
# EC2 Instance + Password Login Enable
#########################################
resource "aws_instance" "APP001-WEB" {
  count         = var.server_count
  ami           = "ami-0b571a36bf02461b4" # Ubuntu 22.04 LTS
  instance_type = "t3.small"

  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.allow_all.id]

  key_name = aws_key_pair.app001-key-r.key_name

  #########################################
  # user_data Script
  #########################################
  user_data = <<-EOF
#!/bin/bash

# Set ubuntu password
echo "ubuntu:Login%12345" | sudo chpasswd

# Find and replace ALL PasswordAuthentication no in /etc/ssh
sudo grep -Rl "PasswordAuthentication no" /etc/ssh | sudo xargs sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g'
sudo grep -Rl "#PasswordAuthentication no" /etc/ssh | sudo xargs sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/g'

# Ensure PAM is enabled
sudo sed -i 's/^#UsePAM no/UsePAM yes/' /etc/ssh/sshd_config
sudo sed -i 's/^UsePAM no/UsePAM yes/' /etc/ssh/sshd_config

# Restart SSH service
sudo systemctl restart sshd
EOF

  tags = {
    Name = format("APP%03d-WEB", count.index + 1)
  }
}

#########################################
# Outputs
#########################################
output "instance_names" {
  value = [for i in aws_instance.APP001-WEB : i.tags["Name"]]
}

output "instance_ids" {
  value = [for i in aws_instance.APP001-WEB : i.id]
}

output "instance_ips" {
  value = [for i in aws_instance.APP001-WEB : i.public_ip]
}

output "instance_dns" {
  value = [for i in aws_instance.APP001-WEB : i.public_dns]
}

output "keyname" {
  value = aws_key_pair.app001-key-r.key_name
}
