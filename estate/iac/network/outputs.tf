locals {
  refs = {
    network = {
      vpc_id                 = aws_vpc.condor.id
      public_subnet_ids      = aws_subnet.public[*].id
      app_subnet_ids         = aws_subnet.app[*].id
      data_subnet_ids        = aws_subnet.data[*].id
      promo_subnet_id        = aws_subnet.promo.id
      reserved_platform_cidr = "10.20.128.0/18"
      hosted_zone_id         = aws_route53_zone.condor_internal.zone_id
      nat_public_ip          = aws_eip.nat.public_ip
    }
  }
}

resource "local_file" "refs" {
  filename = "${path.module}/../../verify/refs.json"
  content  = jsonencode(local.refs)
}

# Mirrored to SSM so a later platform task (P2-01, applied as dp-deployer,
# a different Terraform state) can read this VPC's IDs via a data source
# instead of estate/platform state ever touching each other.
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/condor/network/vpc_id"
  type  = "String"
  value = aws_vpc.condor.id
}

resource "aws_ssm_parameter" "reserved_platform_cidr" {
  name  = "/condor/network/reserved_platform_cidr"
  type  = "String"
  value = "10.20.128.0/18"
}

output "vpc_id" {
  value = aws_vpc.condor.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "promo_subnet_id" {
  value = aws_subnet.promo.id
}

output "hosted_zone_id" {
  value = aws_route53_zone.condor_internal.zone_id
}

output "nat_public_ip" {
  value = aws_eip.nat.public_ip
}
