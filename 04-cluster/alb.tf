# ================================================================================
# FILE: alb.tf
# ================================================================================
#
# Purpose:
#   Deploy an internet-facing Application Load Balancer (ALB) for
#   VS Code and configure backend routing.
#
# Scope:
#   - Application Load Balancer (public)
#   - Target group (HTTP:8080) with stickiness + health checks
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
resource "aws_lb" "vscode_alb" {
  name               = "vscode-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  subnets = [
    data.aws_subnet.pub_subnet_1.id,
    data.aws_subnet.pub_subnet_2.id
  ]
}


# ================================================================================
# SECTION: Target Group - VS Code Backend
# ================================================================================

# Defines backend pool for the session broker on port 8080.
resource "aws_lb_target_group" "vscode_alb_tg" {
  name     = "vscode-alb-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.ad_vpc.id

  # Stickiness is mandatory, not an optimization: a user's code-server
  # process runs on one node only, so every request must return there.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  # /healthz answers without a session cookie; probing / would redirect
  # to the login page and make every healthy node look like a 302.
  health_check {
    path                = "/healthz"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200"
  }
}


# ================================================================================
# SECTION: HTTP Listener - Redirect Only
# ================================================================================

# Port 80 exists solely to bounce users to HTTPS. Nothing is served over
# plain HTTP: cleartext is what lets ISP filters classify the sign-in page as
# phishing and lets carriers interfere with the WebSocket upgrade.
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.vscode_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


# ================================================================================
# SECTION: HTTPS Listener
# ================================================================================

# Terminates TLS at the ALB using the imported self-signed certificate, then
# forwards plain HTTP to the broker inside the VPC. The broker itself needs
# no TLS configuration.
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.vscode_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vscode_alb_tg.arn
  }
}
