# ================================================================================
# FILE: alb.tf
# ================================================================================
#
# Purpose:
#   Deploy an internet-facing Application Load Balancer (ALB) for
#   RStudio and configure backend routing.
#
# Scope:
#   - Application Load Balancer (public)
#   - Target group (HTTP:8787) with stickiness + health checks
#   - HTTP listener (port 80) forwarding to target group
#
# Notes:
#   - ALB placed in public subnets.
#   - Backend targets must allow traffic from ALB security group.
#   - Intended for lab/demo; add HTTPS + ACM for production.
#
# ================================================================================


# ================================================================================
# SECTION: Application Load Balancer
# ================================================================================

# Internet-facing ALB placed in public subnets.
resource "aws_lb" "rstudio_alb" {
  name               = "rstudio-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  subnets = [
    data.aws_subnet.pub_subnet_1.id,
    data.aws_subnet.pub_subnet_2.id
  ]
}


# ================================================================================
# SECTION: Target Group - RStudio Backend
# ================================================================================

# Defines backend pool for RStudio instances on port 8787.
resource "aws_lb_target_group" "rstudio_alb_tg" {
  name     = "rstudio-alb-tg"
  port     = 8787
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.ad_vpc.id

  # Enable ALB cookie stickiness for session persistence.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  # Health check configuration for backend validation.
  health_check {
    path                = "/"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200,300-310"
  }
}


# ================================================================================
# SECTION: HTTP Listener
# ================================================================================

# Listens on port 80 and forwards traffic to target group.
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.rstudio_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rstudio_alb_tg.arn
  }
}
