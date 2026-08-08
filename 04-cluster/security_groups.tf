# ================================================================================
# FILE: security_groups.tf
# ================================================================================
#
# Purpose:
#   Define security groups for RStudio application instances and the
#   Application Load Balancer (ALB).
#
# Scope:
#   - RStudio Server security group (TCP 8787 + ICMP)
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
# SECTION: RStudio Server Security Group
# ================================================================================

resource "aws_security_group" "rstudio_sg" {
  name        = "rstudio-security-group"
  description = "Allow RStudio Server (port 8787) access"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # Allow RStudio web access.
  ingress {
    description = "Allow RStudio Server (TCP 8787)"
    from_port   = 8787
    to_port     = 8787
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


# ================================================================================
# SECTION: Application Load Balancer Security Group
# ================================================================================

resource "aws_security_group" "alb_sg" {
  name        = "rstudio-alb-security-group"
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
