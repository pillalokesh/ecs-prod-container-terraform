# Bastion host with SSM access (best practice avoids SSH keys when possible)

resource "aws_security_group" "bastion" {
  count = var.bastion_ami != "" || (var.bastion_ami == "" && length(data.aws_ami.ubuntu) > 0) ? 1 : 0
  name  = "${var.service_name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from administrative IP (or 0.0.0.0/0 for testing)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.service_name}-bastion-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role" "bastion" {
  count = var.bastion_ami != "" || (var.bastion_ami == "" && length(data.aws_ami.ubuntu) > 0) ? 1 : 0
  name  = "${var.service_name}-bastion-role"

  assume_role_policy = data.aws_iam_policy_document.bastion_assume_role.json
}

data "aws_iam_policy_document" "bastion_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.bastion_ami != "" || (var.bastion_ami == "" && length(data.aws_ami.ubuntu) > 0) ? 1 : 0
  role  = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  count = var.bastion_ami != "" || (var.bastion_ami == "" && length(data.aws_ami.ubuntu) > 0) ? 1 : 0
  name  = "${var.service_name}-bastion-profile"
  role  = aws_iam_role.bastion[0].name
}

# lookup the latest Ubuntu 24.04 LTS AMI in the chosen region
# if the user does not supply an explicit `bastion_ami` value.
data "aws_ami" "ubuntu" {
  count       = var.bastion_ami == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    # match any Ubuntu server AMI (jammy/24.04 might not exist in all regions)
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }
}

resource "aws_instance" "bastion" {
  count                  = var.bastion_ami != "" || data.aws_ami.ubuntu[0].id != "" ? 1 : 0
  ami                    = var.bastion_ami != "" ? var.bastion_ami : data.aws_ami.ubuntu[0].id
  instance_type          = var.bastion_instance_type
  subnet_id              = element(module.vpc.public_subnets, 0)
  vpc_security_group_ids = [aws_security_group.bastion[0].id]
  key_name               = var.bastion_key_name
  iam_instance_profile   = aws_iam_instance_profile.bastion[0].name
  associate_public_ip_address = true

  tags = {
    Name        = "${var.service_name}-bastion"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
