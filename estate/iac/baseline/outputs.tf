output "condor_config_bucket" {
  value = aws_s3_bucket.condor_config.id
}

output "condor_trail_bucket" {
  value = aws_s3_bucket.condor_trail.id
}

output "condor_cur_bucket" {
  value = aws_s3_bucket.condor_cur.id
}

output "condor_flowlogs_bucket" {
  value = aws_s3_bucket.condor_flowlogs.id
}
