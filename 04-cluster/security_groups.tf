# ================================================================================
# FILE: security_groups.tf
# ================================================================================
#
# Purpose:
#   Define security groups for VS Code application instances and the
#   Application Load Balancer (ALB).
#
# Scope:
#   - Session broker security group (TCP 8080 from ALB + ICMP)
#   - ALB security group (TCP 80 + ICMP)
#   - Default outbound access enabled
#
# Security Note:
#   - Inbound rules currently allow 0.0.0.0/0.
#   - Intended for lab/testing only.
#   - Restrict to trusted CIDR ranges or VPN in production.
#
# ================================================================================


# ================================================================================
# SECTION: code-server Security Group
# ================================================================================

resource "aws_security_group" "vscode_sg" {
  name        = "vscode-security-group"
  description = "Allow session broker (port 8080) access from the ALB"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # Only the ALB may reach the broker. Per-user code-server instances listen
  # on loopback and are never reachable from the network at all.
  ingress {
    description     = "Allow session broker (TCP 8080) from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow ICMP for diagnostics.
  ingress {
    description = "Allow ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ================================================================================
# SECTION: Application Load Balancer Security Group
# ================================================================================

resource "aws_security_group" "alb_sg" {
  name        = "vscode-alb-security-group"
  description = "Allow ALB (port 80) access"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # Allow HTTP traffic.
  ingress {
    description = "Allow HTTP (TCP 80)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow ICMP for diagnostics.
  ingress {
    description = "Allow ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
