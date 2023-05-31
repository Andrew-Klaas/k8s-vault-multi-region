terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias = "us-east-1"
}

# provider "aws" {
#   region = "us-west-1"
#   alias = "us-west-1"
# }

data "aws_availability_zones" "available" {}
# data "aws_availability_zones" "available_west" {
#   provider = aws.us-west-1
# }

locals {
  cluster_name = "ak-${random_string.suffix.result}"
  cluster_name_west = "ak-${random_string.suffix.result}"
  name = "ak-teleport"
  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

# resource "aws_kms_key" "east-key" {
#   description             = "KMS key 1"
#   deletion_window_in_days = 10
#   provider = aws.us-east-1
# }
# resource "aws_kms_alias" "east-key-alias" {
#   name          = "alias/vault-key"
#   target_key_id = aws_kms_key.east-key.key_id
#   provider = aws.us-east-1
# }
# resource "aws_kms_key" "west-key" {
#   description             = "KMS key 1"
#   deletion_window_in_days = 10
#   provider = aws.us-west-1
# }
# resource "aws_kms_alias" "west-key-alias" {
#   name          = "alias/vault-key"
#   target_key_id = aws_kms_key.west-key.key_id
#   provider = aws.us-west-1
# }

module "vpc-east" {
  providers = {
    aws = aws.us-east-1
  }
  source = "terraform-aws-modules/vpc/aws"
  # version = "3.14.4"
  name = "ak-vpc"
  cidr = "10.0.0.0/16"
  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

# resource "aws_vpc_peering_connection" "east-west-peer" {
#   peer_vpc_id   = module.vpc-east.vpc_id
#   vpc_id        = module.vpc-west.vpc_id
#   peer_region   = "us-east-1"
#   provider      = aws.us-west-1
# }

# module "vpc-west" {
#   providers = {
#     aws = aws.us-west-1
#   }
#   source = "terraform-aws-modules/vpc/aws"
#   version = "3.14.4"
#   name = "ak-vpc-west"
#   cidr = "10.1.0.0/16"
#   azs             = data.aws_availability_zones.available_west.names
#   private_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
#   public_subnets  = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
#   enable_nat_gateway   = true
#   single_nat_gateway   = true
#   enable_dns_hostnames = true
#   tags = {
#     "kubernetes.io/cluster/${local.cluster_name_west}" = "shared"
#   }
#   public_subnet_tags = {
#     "kubernetes.io/cluster/${local.cluster_name_west}" = "shared"
#     "kubernetes.io/role/elb"                      = "1"
#   }
#   private_subnet_tags = {
#     "kubernetes.io/cluster/${local.cluster_name_west}" = "shared"
#     "kubernetes.io/role/internal-elb"             = "1"
#   }
# }

module "eks" {
  providers = {
    aws = aws.us-east-1
  }
  version = "18.7.2"
  source = "terraform-aws-modules/eks/aws"
  //version         = "17.24.0"
  cluster_name    = local.cluster_name
  cluster_version = "1.22"

  subnet_ids = module.vpc-east.private_subnets
  vpc_id     = module.vpc-east.vpc_id

  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }
  // create an s3 bucket for the cluste

  // # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
    ingress_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  eks_managed_node_groups = {
    blue = {}
    green = {
      min_size     = 3
      max_size     = 3
      desired_size = 3

      instance_types = ["t2.nano"]
      tags = {
        ExtraTag = "ak-example"
      }
    }
  }
}

# module "eks-west" {
#   providers = {
#     aws = aws.us-west-1
#   }
#   version = "18.7.2"
#   source = "terraform-aws-modules/eks/aws"
#   //version         = "17.24.0"
#   cluster_name    = local.cluster_name
#   cluster_version = "1.22"

#   subnet_ids = module.vpc-west.private_subnets
#   vpc_id     = module.vpc-west.vpc_id

#   cluster_addons = {
#     coredns = {
#       resolve_conflicts = "OVERWRITE"
#     }
#     kube-proxy = {}
#     vpc-cni = {
#       resolve_conflicts = "OVERWRITE"
#     }
#   }

#   // # Extend cluster security group rules
#   cluster_security_group_additional_rules = {
#     egress_nodes_ephemeral_ports_tcp = {
#       description                = "To node 1025-65535"
#       protocol                   = "tcp"
#       from_port                  = 1025
#       to_port                    = 65535
#       type                       = "egress"
#       source_node_security_group = true
#     }
#     ingress_all = {
#       description = "Node to node all ports/protocols"
#       protocol    = "-1"
#       from_port   = 0
#       to_port     = 0
#       type        = "ingress"
#       cidr_blocks      = ["0.0.0.0/0"]
#       ipv6_cidr_blocks = ["::/0"]
#     }
#     egress_all = {
#       description      = "Node all egress"
#       protocol         = "-1"
#       from_port        = 0
#       to_port          = 0
#       type             = "egress"
#       cidr_blocks      = ["0.0.0.0/0"]
#       ipv6_cidr_blocks = ["::/0"]
#     }
#   }

#   # Extend node-to-node security group rules
#   node_security_group_additional_rules = {
#     ingress_all = {
#       description = "Node to node all ports/protocols"
#       protocol    = "-1"
#       from_port   = 0
#       to_port     = 0
#       type        = "ingress"
#       cidr_blocks      = ["0.0.0.0/0"]
#       ipv6_cidr_blocks = ["::/0"]
#     }
#     egress_all = {
#       description      = "Node all egress"
#       protocol         = "-1"
#       from_port        = 0
#       to_port          = 0
#       type             = "egress"
#       cidr_blocks      = ["0.0.0.0/0"]
#       ipv6_cidr_blocks = ["::/0"]
#     }
#   }

#   eks_managed_node_groups = {
#     blue = {}
#     green = {
#       min_size     = 3
#       max_size     = 3
#       desired_size = 3

#       instance_types = ["t2.micro"]
#       tags = {
#         ExtraTag = "ak-example"
#       }
#     }
#   }
# }


# resource "aws_iam_access_key" "vault_iam_key" {
#   user    = aws_iam_user.vault.name
# }

# resource "aws_iam_user" "vault" {
#   name = "vault"
#   # path = "/system/"
# }

# data "aws_iam_policy_document" "vault_ro" {
#   statement {
#     effect    = "Allow"
#     actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt"]
#     resources = ["*"]
#   }
# }

# resource "aws_iam_user_policy" "vault_user_policy" {
#   name   = "test"
#   user   = aws_iam_user.vault.name
#   policy = data.aws_iam_policy_document.vault_ro.json
# }

# output "VAULT_AWS_ACCESS_KEY_ID" {
#   value = aws_iam_access_key.vault_iam_key.id
# }

# output "VAULT_AWS_SECRET_ACCESS_KEY" {
#   value = aws_iam_access_key.vault_iam_key.secret
#   sensitive = true
# }