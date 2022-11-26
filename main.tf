# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}
#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}





#Create the VPC
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




#Createa security group

resource "aws_security_group" "allow_tls" {
  name        = "project-security-group"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

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
    description = "MYSQL"
    from_port   = 3306
    to_port     = 3306
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

  tags = {
    Name      = "Project_security_group_allow"
    Terraform = "true"
  }
}





# #Create ASG


module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.5.3"
  # Autoscaling group
  name                      = "project-team1"
  min_size                  = 3
  max_size                  = 5
  desired_capacity          = 3
  wait_for_capacity_timeout = 0
  vpc_zone_identifier       = [for subnet in aws_subnet.public_subnets : subnet.id]
  health_check_type         = "EC2"
  depends_on                = [module.alb]


  # Launch template
  launch_template_name        = "project-tmp"
  launch_template_description = "Project Launch template "
  update_default_version      = true
  image_id                    = "ami-0b0dcb5067f052a63"
  instance_type               = "t3.micro"
  ebs_optimized               = false
  enable_monitoring           = false
  user_data                   = base64encode(data.template_file.user_data.rendered)
  target_group_arns           = module.alb.target_group_arns
  security_groups = [
    aws_security_group.allow_tls.id
  ]

  tags = {
    Name      = "Project_Auto_Scaling_Group"
    Terraform = "true"
  }
}


#Create ALB

module "alb" {
  source                           = "terraform-aws-modules/alb/aws"
  version                          = "~> 8.0"
  name                             = "Project-alb"
  load_balancer_type               = "application"
  enable_cross_zone_load_balancing = true
  vpc_id                           = aws_vpc.vpc.id
  subnets                          = [for subnet in aws_subnet.public_subnets : subnet.id]
  depends_on                       = [aws_db_instance.wordpressdb]

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
  tags = {
    Name      = "Project_Application_Load_Balancer"
    Terraform = "true"
  }
}


# Create RDS instance

#create subnet group for RDS

resource "aws_db_subnet_group" "RDS_subnet_grp" {
  subnet_ids = ["${aws_subnet.public_subnets["public_subnet_1"].id}", "${aws_subnet.public_subnets["public_subnet_2"].id}"]

  tags = {
    Name      = "Project_subnet_group"
    Terraform = "true"
  }
}

#Create security group for RDS

resource "aws_security_group" "RDS_allow_rule" {
  name        = "project-RDS-security-group"
  description = "Allow port 3306 from project-security-group"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.allow_tls.id}"]
  }
  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "Project_RDS-security-group"
    Terraform = "true"
  }

}

# Create Wordpress Database

resource "random_string" "rds_password" {
  length  = 10
  special = false
}


resource "random_string" "suffix" {
  length  = 4
  special = false
}



resource "aws_db_instance" "wordpressdb" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.instance_class
  db_subnet_group_name   = aws_db_subnet_group.RDS_subnet_grp.id
  vpc_security_group_ids = ["${aws_security_group.RDS_allow_rule.id}"]
  db_name                = var.database_name
  username               = var.database_user
  password               = random_string.rds_password.result
  skip_final_snapshot    = true

  # make sure rds manual password change is ignored
  lifecycle {
    ignore_changes = [password]
  }
  tags = {
    Name      = "Project_RDS_Wordpress_Database"
    Terraform = "true"
  }
}


# change USERDATA varible value after grabbing RDS endpoint info
data "template_file" "user_data" {
  template = file("user_data.sh")
  vars = {
    db_username      = var.database_user
    db_user_password = random_string.rds_password.result
    db_name          = var.database_name
    db_RDS           = aws_db_instance.wordpressdb.endpoint
  }
}





#Create Route53 DNS record



resource "aws_route53_record" "alias_route53_record" {
  zone_id = var.zone_id               # Replace with your zone ID
  name    = "wordpress.${var.domain}" # Replace with your name/domain/subdomain
  type    = "A"

  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}



#Outputs

output "RDS-Endpoint" {
  value = aws_db_instance.wordpressdb.endpoint
}

output "rds_password" {
  value = "${random_string.rds_password.result}"
}

output "INFO" {
  value = "AWS Resources and Wordpress has been provisioned. Go to http://wordpress.${var.domain}"
}









