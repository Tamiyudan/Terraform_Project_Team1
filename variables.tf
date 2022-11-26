variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_name" {
  type    = string
  default = "Project_vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}


variable "private_subnets" {
  default = {
    "private_subnet_1" = 1
    "private_subnet_2" = 2
    "private_subnet_3" = 3
  }
}

variable "public_subnets" {
  default = {
    "public_subnet_1" = 1
    "public_subnet_2" = 2
    "public_subnet_3" = 3
  }
}

variable "database_name" {
  default = "wordpress"
  type    = string
}
variable "database_password" {
  default = "test1234"
  type    = string
}
variable "database_user" {
  default = "dbadmin"
  type    = string
}


variable "instance_class" {
  default = "db.t2.micro"
  type    = string
}

variable "zone_id" {}
variable "domain" {}

