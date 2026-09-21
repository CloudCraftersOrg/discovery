resource "aws_db_subnet_group" "pagos" {
  name       = "condor-pagos-db"
  subnet_ids = data.terraform_remote_state.network.outputs.data_subnet_ids
}

resource "aws_security_group" "pagos_db" {
  name        = "condor-pagos-db"
  description = "condor-pagos-db - MySQL from the EKS cluster security group only"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "pagos_db_mysql" {
  security_group_id            = aws_security_group.pagos_db.id
  referenced_security_group_id = aws_eks_cluster.pagos.vpc_config[0].cluster_security_group_id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "pagos_db_all" {
  security_group_id = aws_security_group.pagos_db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_rds_cluster_parameter_group" "pagos" {
  name   = "condor-pagos-params"
  family = "aurora-mysql8.0"
}

resource "aws_rds_cluster" "pagos" {
  cluster_identifier              = "condor-pagos-db"
  engine                          = "aurora-mysql"
  database_name                   = "pagos"
  master_username                 = "pagos"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.pagos.name
  vpc_security_group_ids          = [aws_security_group.pagos_db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pagos.name
  skip_final_snapshot             = true
}

resource "aws_rds_cluster_instance" "pagos" {
  identifier         = "condor-pagos-db-1"
  cluster_identifier = aws_rds_cluster.pagos.id
  instance_class     = "db.t4g.medium"
  engine             = aws_rds_cluster.pagos.engine
  engine_version     = aws_rds_cluster.pagos.engine_version
}
