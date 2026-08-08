# ================================================================================
# FILE: main.tf
# ================================================================================
#
# Purpose:
#   Configure AWS provider and retrieve existing infrastructure components
#   required for RStudio deployment.
#
# Scope:
#   - AWS provider configuration
#   - Secrets Manager lookup (AD admin credentials)
#   - Subnet and VPC discovery
#   - Latest custom RStudio AMI lookup
#   - IAM instance profile lookup
#   - EFS file system lookup
#
# Notes:
#   - Assumes core AD/VPC infrastructure already exists.
#   - Data sources enforce alignment with existing tagged resources.
#
# ================================================================================


# ================================================================================
# SECTION: AWS Provider
# ================================================================================

provider "aws" {
  region = "us-east-1"
}


# ================================================================================
# SECTION: Secrets Manager - AD Admin Credentials
# ================================================================================

data "aws_secretsmanager_secret" "admin_secret" {
  name = "admin_ad_credentials_rstudio"
}


# ================================================================================
# SECTION: VPC Lookup
# ================================================================================

data "aws_vpc" "ad_vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}


# ================================================================================
# SECTION: Subnet Lookups
# ================================================================================

data "aws_subnet" "vm_subnet_1" {
  filter {
    name   = "tag:Name"
    values = ["vm-subnet-1"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}

data "aws_subnet" "vm_subnet_2" {
  filter {
    name   = "tag:Name"
    values = ["vm-subnet-2"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}

data "aws_subnet" "pub_subnet_1" {
  filter {
    name   = "tag:Name"
    values = ["pub-subnet-1"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}

data "aws_subnet" "pub_subnet_2" {
  filter {
    name   = "tag:Name"
    values = ["pub-subnet-2"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}

data "aws_subnet" "ad_subnet" {
  filter {
    name   = "tag:Name"
    values = ["ad-subnet"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ad_vpc.id]
  }
}


# ================================================================================
# SECTION: AMI Lookup - Latest RStudio Image
# ================================================================================

data "aws_ami" "latest_rstudio_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["rstudio_ami*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  owners = ["self"]
}


# ================================================================================
# SECTION: IAM Instance Profile Lookup
# ================================================================================

data "aws_iam_instance_profile" "ec2_secrets_profile" {
  name = "tf-secrets-profile-${lower(var.netbios)}"
}


# ================================================================================
# SECTION: EFS File System Lookup
# ================================================================================

data "aws_efs_file_system" "efs" {
  tags = {
    Name = "rstudio-efs"
  }
}
