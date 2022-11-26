## Wordpress on AWS

Provision Wordpress on AWS using Terraform.


### Requirements:
1. AWS Account.
2. IAM User with Admin privileges.
3. Terraform installed.

### How to Use:
1. rename `user.tfvars.sample` to `terraform.tfvars` and fill in the variables.
2. `terraform init`
3. `terraform plan`
4. `terraform apply`
5. `terraform destroy` - will destroy all resources.

### AWS Resources created:
1 x VPC

3 x Private Subnets  

3 x Public Subnets  

1 x Database Subnet Group 

1 x NAT Gateway   

1 x RDS MySQL  

1 x ALB  

1 x ASG

1 x Route53 DNS Record
 
