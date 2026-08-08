# ################################################################################
# FILE: debug_instance.tf
# ################################################################################
# !! TEMPORARY DEBUG CONFIGURATION - DELETE BEFORE NORMAL USE !!
# ################################################################################
#
# Purpose:
#   Replace the autoscaling cluster with a single standalone EC2 instance
#   while the session broker is being debugged. Removes the ASG, ALB, and
#   launch template from the picture so a failing bootstrap cannot cycle
#   instances mid-investigation.
#
# What is disabled alongside this file:
#   alb.tf.disabled  asg.tf.disabled  lt.tf.disabled
#
# To restore normal operation:
#   1. Delete this file.
#   2. Rename the three .disabled files back to .tf.
#   3. Revert the DEBUG block in security_groups.tf (port 8080 ingress).
#
# Differences from a cluster node, all deliberate for debugging:
#   - Public subnet with a public IP, since there is no ALB to front it.
#   - Port 8080 reachable directly from the internet.
#   - Runs the identical scripts/vscode_booter.sh, so the bootstrap path
#     under test is the same one the cluster uses.
#
# ================================================================================


# ================================================================================
# SECTION: Standalone Debug Instance
# ================================================================================

resource "aws_instance" "vscode_debug" {
  ami           = data.aws_ami.latest_vscode_ami.id
  instance_type = "m5.large"

  # Public subnet + public IP: no load balancer exists in this mode, so the
  # browser needs a route to the broker that is not SSM port forwarding.
  subnet_id                   = data.aws_subnet.pub_subnet_1.id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.vscode_sg.id]

  # Same profile the cluster nodes use — Secrets Manager for the AD join
  # credential, plus SSM for shell access.
  iam_instance_profile = data.aws_iam_instance_profile.ec2_secrets_profile.name

  root_block_device {
    volume_size           = 16
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # Identical bootstrap to the launch template, so what is exercised here is
  # what the cluster will run.
  user_data = templatefile("./scripts/vscode_booter.sh", {
    admin_secret   = "admin_ad_credentials_vscode"
    domain_fqdn    = var.dns_zone
    efs_mnt_server = data.aws_efs_file_system.efs.dns_name
    netbios        = var.netbios
    realm          = var.realm
    force_group    = "vscode-users"
  })

  tags = {
    Name = "vscode-debug-instance"
  }
}


# ================================================================================
# SECTION: Connection Details
# ================================================================================

output "debug_instance_id" {
  description = "Instance ID for SSM sessions and port forwarding"
  value       = aws_instance.vscode_debug.id
}

output "debug_public_dns" {
  description = "Public DNS name of the standalone debug instance"
  value       = aws_instance.vscode_debug.public_dns
}

output "debug_broker_url" {
  description = "Direct URL to the session broker on the debug instance"
  value       = "http://${aws_instance.vscode_debug.public_dns}:8080"
}
