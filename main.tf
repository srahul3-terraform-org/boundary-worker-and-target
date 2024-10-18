# doormat aws tf-push --workspace boundary-worker-and-target --organization srahul3 --account 980777455695

# Define the provider
provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"

  name = "boundary_exp_vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a"]
  private_subnets = ["10.0.1.0/24"]
  public_subnets  = ["10.0.2.0/24"]

  enable_nat_gateway   = true
  enable_vpn_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Create a security group
resource "aws_security_group" "boundary_worker_sg" {
  vpc_id = module.vpc.vpc_id
  name   = "boundary_worker_sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9202
    to_port     = 9202
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
    Name = "boundary_worker_sg" // may not be needed but good for human readability
  }
}

# Create an EC2 instance
resource "aws_instance" "worker_instance" {
  ami                         = "ami-0aff18ec83b712f05" # Update this to the latest Amazon Linux 2 AMI in your region
  instance_type               = "t2.small"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.boundary_worker_sg.id]
  key_name                    = "nomad" # Specify the existing key pair name
  associate_public_ip_address = true    # Enable public IP

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y jq unzip
              wget -q "$(curl -fsSL 'https://api.releases.hashicorp.com/v1/releases/boundary/latest?license_class=enterprise' | jq -r '.builds[] | select(.arch == 'amd64' and .os == 'linux') | .url')"
              unzip *.zip
              EOF

  tags = {
    Name = "BoundaryWorker"
  }
}

# Create a security group with ssh enbaled
resource "aws_security_group" "boundary_target_sg" {
  vpc_id = module.vpc.vpc_id
  name   = "boundary_target_sg"

  ingress {
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

  tags = {
    Name = "BoundaryTarget" // may not be needed but good for human readability
  }
}

# Create an EC2 traget
resource "aws_instance" "worker_instance" {
  ami                         = "ami-0aff18ec83b712f05" # Update this to the latest Amazon Linux 2 AMI in your region
  instance_type               = "t2.small"
  subnet_id                   = module.vpc.private_subnets[0]
  vpc_security_group_ids      = [aws_security_group.boundary_target_sg.id]
  key_name                    = "nomad" # Specify the existing key pair name
  associate_public_ip_address = false    # disable public IP

  tags = {
    Name = "BoundaryTarget"
  }
}

# Output the public IP of the EC2 instance
output "instance_public_ip" {
  value = aws_instance.worker_instance.public_ip
}

# Output the public DNS of the EC2 instance
output "instance_public_dns" {
  value = aws_instance.worker_instance.public_dns
}
