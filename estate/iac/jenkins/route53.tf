resource "aws_route53_record" "jenkins" {
  zone_id = data.terraform_remote_state.network.outputs.hosted_zone_id
  name    = "jenkins.condor.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.jenkins.private_ip]
}
