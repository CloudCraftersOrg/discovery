resource "aws_route53_zone" "condor_internal" {
  name = "condor.internal"

  vpc {
    vpc_id = aws_vpc.condor.id
  }

  tags = {
    Name = "condor-internal"
  }
}
