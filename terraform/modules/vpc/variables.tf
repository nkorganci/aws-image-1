// filepath: d:\workspace\aws-image-1\terraform\modules\vpc\variables.tf
variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet CIDRs"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet CIDRs"
  type        = list(string)
}

variable "public_azs" {
  description = "List of AZs for public subnets"
  type        = list(string)
}

variable "private_azs" {
  description = "List of AZs for private subnets"
  type        = list(string)
}

