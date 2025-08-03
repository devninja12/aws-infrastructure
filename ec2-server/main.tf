terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# Get the default VPC in the region
data "aws_vpc" "default" {
  default = true
}

# Security Group in default VPC to allow SSH
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance in default VPC, using the SG by ID
resource "aws_instance" "web" {
  ami                    = "ami-068d5d5ed1eeea07c" # Amazon Linux 2 in us-east-2 (replace with your preferred AMI)
  instance_type          = "t3.small"
  key_name               = "terraform-key"
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              echo "Welcome to Terraform EC2" > /var/www/html/index.html
              EOF

  tags = {
    Name = "TerraformEC2"
  }
}


# Outputs for instance info
output "instance_id" {
  value = aws_instance.web.id
}

output "instance_public_ip" {
  value = aws_instance.web.public_ip
}
