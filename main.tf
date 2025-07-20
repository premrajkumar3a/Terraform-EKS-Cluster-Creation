# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

# Filter out local zones, which are not currently supported 
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  cluster_name = "PREM-EKS-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

#Routing tables and other are taken care by vpc module internally
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "DEV-VPC"

  cidr = "192.168.10.0/25"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["192.168.10.16/27", "192.168.10.32/27", "192.168.10.64/28"]
  public_subnets  = ["192.168.10.80/28", "192.168.10.96/28", "192.168.10.112/28"]

# we private instance needs internet connect we achieve it using NAT Gateway
  enable_nat_gateway   = true
# we are use using single NAT gateway for 3 public subnets
  single_nat_gateway   = true 
  enable_dns_hostnames = true

# LB created in Public subnet is accessible from internet
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

# LB created in private subnet is only accesible within VPC
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
 # module version
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = "1.30"

# we want to access the cluster from outside so we enabled it.
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

/*
  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }
*/
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

# Internally these nodegroups will create AutoScaling Group
  eks_managed_node_groups = {
    bastion = {
      name = "bastion"

      instance_types = ["t2.micro"]

      min_size     = 0
      max_size     = 1
      desired_size = 1
    }

    reactjs = {
      name = "Frontend"

      instance_types = ["t2.micro"]

      min_size     = 0
      max_size     = 1
      desired_size = 1
    }
    java = {
      name = "Backend"

      instance_types = ["t2.micro"]

      min_size     = 0
      max_size     = 2
      desired_size = 1
    }
   database = {
      name = "Databse"

      instance_types = ["t2.micro"]

      min_size     = 0
      max_size     = 2
      desired_size = 1
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

/*
module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}
*/
