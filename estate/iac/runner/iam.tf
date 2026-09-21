data "aws_iam_policy_document" "runner_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  name               = "condor-gh-runner-instance-role"
  assume_role_policy = data.aws_iam_policy_document.runner_trust.json
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "runner" {
  name = "condor-gh-runner-instance-profile"
  role = aws_iam_role.runner.name
}
