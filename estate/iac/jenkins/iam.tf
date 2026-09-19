# AdministratorAccess on the instance profile, compensated only by the
# boundary every planted admin identity gets (CLAUDE.md #4) — PLANTED: AK-PIP-05.
data "aws_iam_policy_document" "jenkins_instance_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins_instance" {
  name                 = "condor-jenkins-instance-role"
  assume_role_policy   = data.aws_iam_policy_document.jenkins_instance_trust.json
  permissions_boundary = data.aws_iam_policy.condor_sandbox_boundary.arn
}

resource "aws_iam_role_policy_attachment" "jenkins_instance_admin" {
  role       = aws_iam_role.jenkins_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "jenkins_instance" {
  name = "condor-jenkins-instance-profile"
  role = aws_iam_role.jenkins_instance.name
}
