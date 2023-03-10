# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "profile" {
  description = "AWS profile"
  type        = string
  default     = "personal"
}

variable "eks-cluster-version" {
  description = "AWS EKS cluster version"
  type        = string
  default     = "1.24"
}

variable "vpc-cidr" {
  description = "AWS VPC CIDR block"
  type        = string
  default     = "172.22.0.0/16"
}

variable "vpc-private-subnets" {
  description = "AWS VPC private subnets"
  type    = list(string)
  default = ["172.22.0.0/21", "172.22.8.0/21", "172.22.16.0/21"]
}

variable "vpc-public-subnets" {
  description = "AWS VPC public subnets"
  type    = list(string)
  default = ["172.22.250.0/24", "172.22.251.0/24", "172.22.252.0/24"]
}
