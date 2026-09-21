# The NLB is created by the AWS Load Balancer Controller from the chart's
# Service, not by this Terraform - it only exists once deploy.yml has run
# at least once, so this data source only resolves after that first deploy.
data "aws_lb" "pagos" {
  tags = {
    "elbv2.k8s.aws/cluster" = "condor-pagos"
  }
}

resource "aws_route53_record" "pagos" {
  zone_id = data.terraform_remote_state.network.outputs.hosted_zone_id
  name    = "pagos.condor.internal"
  type    = "A"

  # false: on a simple alias, Route 53's own health tracking lags the
  # target group's - returned NOERROR/no-answer while elbv2 already read
  # "healthy". The alarm below catches real incidents instead.
  alias {
    name                   = data.aws_lb.pagos.dns_name
    zone_id                = data.aws_lb.pagos.zone_id
    evaluate_target_health = false
  }
}

# UnHealthyHostCount is only ever published for the LoadBalancer+TargetGroup
# dimension pair together (confirmed via AWS's own NLB metrics reference) -
# LoadBalancer alone never gets data, alarm would sit in INSUFFICIENT_DATA.
data "aws_lb_target_group" "pagos" {
  tags = {
    "elbv2.k8s.aws/cluster" = "condor-pagos"
  }
}

resource "aws_cloudwatch_metric_alarm" "pagos_nlb_unhealthy" {
  alarm_name          = "condor-pagos-nlb-unhealthy-hosts"
  namespace           = "AWS/NetworkELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 2

  dimensions = {
    LoadBalancer = data.aws_lb.pagos.arn_suffix
    TargetGroup  = data.aws_lb_target_group.pagos.arn_suffix
  }
}
