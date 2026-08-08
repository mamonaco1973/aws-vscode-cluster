# ================================================================================
# FILE: vscode_ami.pkr.hcl
# ================================================================================
#
# Purpose:
#   Build a reusable Amazon Machine Image (AMI) carrying code-server and the
#   session broker on Ubuntu 24.04 (Noble) using Packer.
#
# Design:
#   - Base image dynamically resolved from Canonical-owned AMI.
#   - Temporary EC2 instance used for provisioning.
#   - Timestamped AMI name ensures uniqueness per build.
#   - Resulting AMI is consumed by the 04-cluster launch template.
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

# Optional code-server release pin. Empty resolves to the latest upstream
# release, which is convenient during development but not reproducible.
variable "code_server_version" {
  description = "code-server version to install (empty = latest)"
  default     = ""
}


# ================================================================================
# SECTION: Amazon EBS Builder
# ================================================================================

# Launch temporary EC2 instance, provision software, and create AMI.
source "amazon-ebs" "vscode_ami" {
  region        = var.region
  instance_type = var.instance_type
  source_ami    = data.amazon-ami.ubuntu_2404.id
  ssh_username  = "ubuntu"
  ssh_interface = "public_ip"

  ami_name = "vscode_ami_${replace(timestamp(), ":", "-")}"

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
    Name = "vscode_ami_${replace(timestamp(), ":", "-")}"
  }
}


# ================================================================================
# SECTION: Provisioning Steps
# ================================================================================

# Execute provisioning scripts within temporary build instance.
build {
  sources = ["source.amazon-ebs.vscode_ami"]

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

  # Install and configure code-server.
  provisioner "shell" {
    script           = "./vscode.sh"
    execute_command  = "sudo -E bash '{{.Path}}'"
    environment_vars = ["CODE_SERVER_VERSION=${var.code_server_version}"]
  }

  # Stage broker sources where broker.sh expects to find them.
  provisioner "file" {
    source      = "./broker"
    destination = "/tmp"
  }

  # Install the session broker and its systemd unit.
  provisioner "shell" {
    script          = "./broker.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }
}
