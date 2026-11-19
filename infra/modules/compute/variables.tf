# modules/compute/variables.tf

variable "identifier" {
  type        = string
  description = "项目标识"
}

variable "vpc_name" {
  type        = string
  description = "所属 spoke VPC 名称（用于资源命名与标签）"
}

variable "vpc_id" {
  type        = string
  description = "所属 VPC ID"
}

variable "workload_subnets" {
  type        = list(string)
  description = "按 AZ 顺序的工作负载子网 ID 列表"
}

variable "number_azs" {
  type        = number
  description = "ECS 实例数量（每个一个）"
}

variable "flavor_id" {
  type        = string
  description = "ECS 规格 ID"
}

variable "image_id" {
  type        = string
  description = "镜像 ID"
}

variable "security_group_id" {
  type        = string
  description = "安全组 ID"
}

variable "agency_name" {
  type        = string
  description = "ECS 实例委托名称（用于访问云监控 / OBS）"
}
