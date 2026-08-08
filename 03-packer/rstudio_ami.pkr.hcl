# ================================================================================
# FILE: rstudio.pkr.hcl
# ================================================================================
#
# Purpose:
#   Build a reusable Amazon Machine Image (AMI) for RStudio Server on
#   Ubuntu 24.04 (Noble) using Packer.
#
# Design:
#   - Base image dynamically resolved from Canonical-owned AMI.
#   - Temporary EC2 instance used for provisioning.
#   - Timestamped AMI name ensures uniqueness per build.
#   - Resulting AMI intended for Terraform or direct EC2 launches.
#
# ================================================================================


# ================================================================================
# SECTION: Packer Plugin Configuration
# ================================================================================

# Require official HashiCorp Amazon plugin for AWS interaction.
packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}


# ================================================================================
# SECTION: Base AMI Lookup - Ubuntu 24.04 (Noble)
# ================================================================================

# Select most recent Canonical-owned Ubuntu 24.04 AMI.
# Restrict to HVM virtualization and EBS-backed root volume.
data "amazon-ami" "ubuntu_2404" {
  filters = {
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    virtualization-type = "hvm"
    root-device-type    = "ebs"
  }

  most_recent = true
  owners      = ["099720109477"]
}


# ================================================================================
# SECTION: Build-Time Variables
# ================================================================================

# AWS region for build execution.
variable "region" {
  default = "us-east-1"
}

# Instance type for temporary build host.
# Larger instance reduces provisioning time.
variable "instance_type" {
  default = "m5.large"
}

# Target VPC for build instance.
variable "vpc_id" {
  description = "VPC ID for build instance"
  default     = ""
}

# Target subnet for build instance (requires outbound internet).
variable "subnet_id" {
  description = "Subnet ID for build instance"
  default     = ""
}


# ================================================================================
# SECTION: Amazon EBS Builder
# ================================================================================

# Launch temporary EC2 instance, provision software, and create AMI.
source "amazon-ebs" "rstudio_ami" {
  region        = var.region
  instance_type = var.instance_type
  source_ami    = data.amazon-ami.ubuntu_2404.id
  ssh_username  = "ubuntu"
  ssh_interface = "public_ip"

  ami_name = "rstudio_ami_${replace(timestamp(), ":", "-")}"

  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id

  # Root volume configuration.
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = "16"
    volume_type           = "gp3"
    delete_on_termination = "true"
  }

  tags = {
    Name = "rstudio_ami_${replace(timestamp(), ":", "-")}"
  }
}


# ================================================================================
# SECTION: Provisioning Steps
# ================================================================================

# Execute provisioning scripts within temporary build instance.
build {
  sources = ["source.amazon-ebs.rstudio_ami"]

  # Install SSM agent.
  provisioner "shell" {
    script          = "./ssm.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install base packages.
  provisioner "shell" {
    script          = "./packages.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install AWS CLI.
  provisioner "shell" {
    script          = "./awscli.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install and configure RStudio Server.
  provisioner "shell" {
    script          = "./rstudio.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }
}
