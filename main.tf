# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = module.eks.cluster_arn
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = module.eks.cluster_arn
}
provider "aws" {
  region  = var.region
  profile = var.profile

  assume_role {
    # The role ARN within Account B to AssumeRole into. Created in step 1.
    role_arn = var.role_arn
    # (Optional) The external ID created in step 1c.
    #external_id = "my_external_id"
  }
}

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "${var.environment}-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "${local.cluster_name}-vpc"

  cidr = var.vpc-cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = var.vpc-private-subnets
  public_subnets  = var.vpc-public-subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.5.1"

  cluster_name    = local.cluster_name
  cluster_version = var.eks-cluster-version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type      = "AL2_x86_64"
    capacity_type = "SPOT"

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.small"]

      capacity_type = "ON_DEMAND"

      min_size     = 1
      max_size     = 4
      desired_size = 3
    }

    two = {
      name = "node-group-2"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.5.2-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}

resource "aws_eip" "static-nlb-eip" {
  count = length(module.vpc.public_subnets)

  tags = {
    "Name" = "${module.eks.cluster_name}-static-nlb-eip"
  }

  vpc = true
}

# resource "aws_lb" "static-nlb" {
#   name               = "${var.environment}-static-nlb"
#   internal           = false
#   load_balancer_type = "network"
#   # subnets            = [for subnet in module.vpc.public_subnets : subnet]

#   dynamic "subnet_mapping" {
#     for_each = range(length(module.vpc.public_subnets))

#     content {
#       subnet_id     = module.vpc.public_subnets[subnet_mapping.key]
#       allocation_id = lookup(aws_eip.static-nlb-eip[subnet_mapping.key], "id")
#     }
#   }

#   enable_deletion_protection = true

#   # access_logs {
#   #   bucket  = aws_s3_bucket.lb_logs.id
#   #   prefix  = "static-nlb"
#   #   enabled = true
#   # }

#   tags = {
#     Environment = "${var.environment}"
#   }
# }

# deploy Kong Gateway Enterprise
resource "kubernetes_namespace" "kong" {
  metadata {
    name = "kong"
  }
}

resource "helm_release" "kong-ingress" {
  name      = "kong-ingress"
  namespace = kubernetes_namespace.kong.metadata[0].name

  repository = "https://charts.konghq.com"
  chart      = "kong"
  # version    = "2.16.5"

  values = [
    "${file("kongconfig/values.yaml")}"
  ]

  set {
    name  = "proxy.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-eip-allocations"
    value = join("\\,", aws_eip.static-nlb-eip[*].id)
    type  = "string"
  }

  set {
    name  = "proxy.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-subnets"
    value = join("\\,", module.vpc.public_subnets)
    type  = "string"
  }

  depends_on = [module.eks]
}