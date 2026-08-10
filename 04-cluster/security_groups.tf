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
#   - ALB security group (TCP 80 redirect + TCP 443 + ICMP)
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

  # Only the ALB may reach the broker, and TLS terminates there. Per-user
  # code-server instances listen on loopback and are never reachable from
  # the network at all.
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
  description = "Allow ALB (ports 80 and 443) access"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # Port 80 is redirect-only; nothing is served in cleartext.
  ingress {
    description = "Allow HTTP (TCP 80) for redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS traffic — the only listener that serves content.
  ingress {
    description = "Allow HTTPS (TCP 443)"
    from_port   = 443
    to_port     = 443
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
