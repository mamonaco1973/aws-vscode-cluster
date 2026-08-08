# ================================================================================
# FILE: launch_template.tf
# ================================================================================
#
# Purpose:
#   Define EC2 launch configuration for VS Code instances used by the Auto
#   Scaling Group (ASG). Includes storage, networking, IAM, AMI selection,
#   and bootstrapping user data.
#
# Design:
#   - Private instances (no public IP) launched via ASG.
#   - Root volume encrypted and deleted on termination.
#   - IAM instance profile enables secrets and management integration.
#   - User data rendered and base64-encoded for instance bootstrap.
#
# ================================================================================


# ================================================================================
# SECTION: Launch Template - VS Code Instances
# ================================================================================

resource "aws_launch_template" "vscode_launch_template" {
  name        = "vscode-launch-template"
  description = "Launch template for vscode autoscaling"


  # --------------------------------------------------------------------------
  # Root Block Device
  # --------------------------------------------------------------------------
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      volume_size           = 16
      volume_type           = "gp3"
      encrypted             = true
    }
  }


  # --------------------------------------------------------------------------
  # Network Interface
  # --------------------------------------------------------------------------
  # Instances are launched without public IPs.
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups = [
      aws_security_group.vscode_sg.id
    ]
  }


  # --------------------------------------------------------------------------
  # IAM Instance Profile
  # --------------------------------------------------------------------------
  # Provides access to required AWS APIs (e.g., Secrets Manager).
  iam_instance_profile {
    name = data.aws_iam_instance_profile.ec2_secrets_profile.name
  }


  # --------------------------------------------------------------------------
  # Instance Settings
  # --------------------------------------------------------------------------
  instance_type = "m5.large"
  image_id      = data.aws_ami.latest_vscode_ami.id


  # --------------------------------------------------------------------------
  # User Data Bootstrapping
  # --------------------------------------------------------------------------
  user_data = base64encode(templatefile("./scripts/vscode_booter.sh", {
    admin_secret   = "admin_ad_credentials_vscode"
    domain_fqdn    = var.dns_zone
    efs_mnt_server = data.aws_efs_file_system.efs.dns_name
    netbios        = var.netbios
    realm          = var.realm
    force_group    = "vscode-users"
  }))


  # --------------------------------------------------------------------------
  # Tags
  # --------------------------------------------------------------------------
  tags = {
    Name = "vscode-launch-template"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "vscode-instance"
    }
  }
}
