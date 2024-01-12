data "aws_ami" "ubuntu" {
    most_recent = true
    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    }
    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
    owners = ["099720109477"]
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = var.public_key
}


resource "aws_instance" "mongodb-ec2-instance" {
    ami = data.aws_ami.ubuntu.id
    instance_type = "t2.small"
    tags = {
        Name = "mongodb-ec2-instance"
    }

    associate_public_ip_address = true
    subnet_id = module.vpc-east.public_subnets[0]
    key_name = resource.aws_key_pair.deployer.key_name
    security_groups = [ aws_security_group.allow_ssh_mongodb.id ]
    iam_instance_profile = aws_iam_instance_profile.mongodb-ec2-instance-profile.id
    user_data = templatefile("./init.sh", {
        # public_key = var.public_key
    })
}

resource "aws_iam_instance_profile" "mongodb-ec2-instance-profile" {
    name = "mongodb-ec2-instance-profile"
    role = aws_iam_role.mongodb-ec2-role.name
}
resource "aws_iam_role" "mongodb-ec2-role" {
  name = "examplerole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  inline_policy {
    name = "my_inline_policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["ec2:*"]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }
}

#create security group resources with ingress on 22 and 27017 and egress on all ports
resource "aws_security_group" "allow_ssh_mongodb" {
  name        = "allow_ssh_mongodb"
  description = "Allow inbound traffic on SSH/Mongodb and all outbound traffic"
  vpc_id      = module.vpc-east.vpc_id
  tags = {
    Name = "allow_ssh_mongodb"
  }
}
resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.allow_ssh_mongodb.id
  cidr_ipv4         = module.vpc-east.vpc_cidr_block
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}
resource "aws_vpc_security_group_ingress_rule" "allow_mongodb" {
  security_group_id = aws_security_group.allow_ssh_mongodb.id
  cidr_ipv4         = module.vpc-east.vpc_cidr_block
  from_port         = 27017
  ip_protocol       = "tcp"
  to_port           = 27017
}
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_ssh_mongodb.id 
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

