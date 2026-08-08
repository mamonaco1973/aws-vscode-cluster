# ================================================================================
# FILE: autoscaling.tf
# ================================================================================
#
# Purpose:
#   Provide horizontal scaling for RStudio infrastructure using:
#     - CloudWatch CPU alarm
#     - Auto Scaling policy
#     - Auto Scaling Group (ASG)
#
# Design:
#   - Scale up when average CPU > 60% for 1 minute.
#   - Increase capacity by 1 instance per alarm event.
#   - Integrate with ALB target group for health monitoring.
#
# Notes:
#   - Only scale-up policy defined here (no scale-down policy).
#   - Grace period and warmup aligned at 300 seconds.
#   - Instances distributed across private VM subnets.
#
# ================================================================================


# ================================================================================
# SECTION: CloudWatch Alarm - High CPU
# ================================================================================

# Trigger scaling action when CPU utilization exceeds threshold.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "HighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 30
  statistic           = "Average"
  threshold           = 60
  alarm_description   = "Scale up if CPUUtilization > 60% for 1 minute"
  actions_enabled     = true

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.rstudio_asg.name
  }

  alarm_actions = [
    aws_autoscaling_policy.scale_up_policy.arn
  ]
}


# ================================================================================
# SECTION: Auto Scaling Policy - Scale Up
# ================================================================================

# Increase ASG capacity by one instance per alarm event.
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale-up-policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 120
  autoscaling_group_name = aws_autoscaling_group.rstudio_asg.name
}


# ================================================================================
# SECTION: Auto Scaling Group (ASG)
# ================================================================================

# Manage lifecycle of RStudio EC2 instances.
resource "aws_autoscaling_group" "rstudio_asg" {

  launch_template {
    id      = aws_launch_template.rstudio_launch_template.id
    version = "$Latest"
  }

  name = "rstudio-asg"

  vpc_zone_identifier = [
    data.aws_subnet.vm_subnet_1.id,
    data.aws_subnet.vm_subnet_2.id
  ]

  desired_capacity          = 2
  max_size                  = 4
  min_size                  = 2
  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_cooldown          = 120
  default_instance_warmup   = 300

  target_group_arns = [
    aws_lb_target_group.rstudio_alb_tg.arn
  ]

  depends_on = [
    aws_lb.rstudio_alb
  ]
}
