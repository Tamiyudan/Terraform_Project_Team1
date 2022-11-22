# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}
#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
#Define the VPC
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = var.vpc_name
    Environment = "Project_environment"
    Terraform   = "true"
  }
}




#Deploy the private subnets

resource "aws_subnet" "private_subnets" {
  for_each   = var.private_subnets
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = tolist(data.aws_availability_zones.available.names)[
  each.value]
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each   = var.public_subnets
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone = tolist(data.aws_availability_zones.available.
  names)[each.value]
  map_public_ip_on_launch = true
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Create route tables for public and private subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id

    #nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "Project_public_route_table"
    Terraform = "true"
  }
}
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"

    # gateway_id = aws_internet_gateway.internet_gateway.id

    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "Project_private_route_table"
    Terraform = "true"
  }
}

#Create route table associations
resource "aws_route_table_association" "public" {
  depends_on     = [aws_subnet.public_subnets]
  route_table_id = aws_route_table.public_route_table.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}
resource "aws_route_table_association" "private" {
  depends_on     = [aws_subnet.private_subnets]
  route_table_id = aws_route_table.private_route_table.id
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
}
#Create Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "project_igw"
  }
}
#Create EIP for NAT Gateway
resource "aws_eip" "nat_gateway_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "project_igw_eip"
  }
}
#Create NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on    = [aws_subnet.public_subnets]
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name = "project_nat_gateway"
  }
}


module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.5.3"
  # Autoscaling group
  name                      = "project-asg"
  min_size                  = 3
  max_size                  = 10
  desired_capacity          = 3
  wait_for_capacity_timeout = 0
  vpc_zone_identifier       = [for subnet in aws_subnet.public_subnets : subnet.id]
  health_check_type         = "EC2"
  depends_on     = [module.alb]



  # Launch template
  launch_template_name        = "project-tmp"
  launch_template_description = "Project Launch template "
  update_default_version      = true
  image_id                    = "ami-0b0dcb5067f052a63"
  instance_type               = "t3.micro"
  ebs_optimized               = false
  enable_monitoring           = false
  user_data                   = "IyEvYmluL2Jhc2ggCgp5dW0gaW5zdGFsbCBodHRwZCB3Z2V0IHVuemlwIGVwZWwtcmVsZWFzZSBteXNxbCAteSAKCnN1ZG8gYW1hem9uLWxpbnV4LWV4dHJhcyBpbnN0YWxsIGVwZWwgLXkgCgp5dW0gLXkgaW5zdGFsbCBodHRwczovL3JwbXMucmVtaXJlcG8ubmV0L2VudGVycHJpc2UvcmVtaS1yZWxlYXNlLTcucnBtIAoKeXVtLWNvbmZpZy1tYW5hZ2VyIC0tZW5hYmxlIHJlbWktcGhwNzQgCgp5dW0gaW5zdGFsbCBwaHAgLXkgCgp5dW0gaW5zdGFsbCBwaHAtbXlzcWwgLXkgCgogCndnZXQgaHR0cDovL3dvcmRwcmVzcy5vcmcvd29yZHByZXNzLTQuMC4zMi50YXIuZ3ogIAoKIAp0YXIgLXhmIHdvcmRwcmVzcy00LjAuMzIudGFyLmd6IC1DIC92YXIvd3d3L2h0bWwvIAoKbXYgL3Zhci93d3cvaHRtbC93b3JkcHJlc3MvKiAvdmFyL3d3dy9odG1sLyAgCgpHZXRlbmZvcmNlIAoKc2VkICdzL1NFTElOVVg9cGVybWlzc2l2ZS9TRUxJTlVYPWVuZm9yY2luZy9nJyAvZXRjL3N5c2NvbmZpZy9zZWxpbnV4IC1pICAKc2V0ZW5mb3JjZSAwIAogCmNob3duIC1SIGFwYWNoZTphcGFjaGUgL3Zhci93d3cvaHRtbC8gCiAKc3VkbyBzeXN0ZW1jdGwgcmVzdGFydCBodHRwZCAKIApzdWRvIHN5c3RlbWN0bCBlbmFibGUgaHR0cGQg"
  target_group_arns           = module.alb.target_group_arns
  security_groups = [
    aws_security_group.allow_tls.id
  ]
}


resource "aws_security_group" "allow_tls" {
  name        = "project-security-group"
  description = "Allow TLS inbound traffic"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}


module "alb" {
  source             = "terraform-aws-modules/alb/aws"
  version            = "~> 8.0"
  name               = "Project-alb"
  load_balancer_type = "application"
  enable_cross_zone_load_balancing = true
  vpc_id             = aws_vpc.vpc.id
  subnets = [for subnet in aws_subnet.public_subnets : subnet.id]

  security_groups = [
    aws_security_group.allow_tls.id
  ]

  target_groups = [
    {
      name_prefix      = "pref-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]
}

