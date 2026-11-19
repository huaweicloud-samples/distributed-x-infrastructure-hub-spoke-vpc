# variables.tf — 输入变量

variable "region" {
  type        = string
  description = "华为云区域代码"
  default     = "cn-north-4"
}

variable "identifier" {
  type        = string
  description = "项目标识，作为资源命名后缀"
  default     = "hubspoke-shared-services"
}

variable "availability_zones" {
  type        = list(string)
  description = "可用区列表（按 region 内顺序；默认前 N 个）"
  default     = ["cn-north-4a", "cn-north-4b", "cn-north-4c"]
}

# 工作负载 VPC（spoke）
variable "vpcs" {
  type        = any
  description = "Spoke 工作负载 VPC 定义"
  default = {
    "spoke-vpc-1" = {
      cidr_block       = "10.0.0.0/24"
      workload_subnets = ["10.0.0.0/26", "10.0.0.64/26", "10.0.0.128/26"]
      transit_subnets  = ["10.0.0.192/28", "10.0.0.208/28", "10.0.0.224/28"]
      number_azs       = 2
      instance_flavor  = "s6.small.1"
      image_name       = "CentOS 7.9 64bit"
      flow_log_config = {
        retention_in_days = 7
      }
    }
    "spoke-vpc-2" = {
      cidr_block       = "10.0.1.0/24"
      workload_subnets = ["10.0.0.0/26", "10.0.1.64/26", "10.0.1.128/26"]
      transit_subnets      = ["10.0.1.192/28", "10.0.1.208/28", "10.0.1.224/28"]
      number_azs       = 2
      instance_flavor  = "s6.small.1"
      image_name       = "CentOS 7.9 64bit"
      flow_log_config = {
        retention_in_days = 7
      }
    }
  }
}

# 共享服务 VPC
variable "shared_services_vpc" {
  type        = any
  description = "共享服务 VPC 配置"
  default = {
    cidr_block               = "10.129.0.0/24"
    endpoints_subnet_netmask = 28
    transit_subnet_netmask   = 28
    number_azs               = 2
  }
}

# 混合 DNS — 入站 / 出站
variable "on_premises_cidr" {
  type        = string
  description = "本地数据中心 CIDR（用于入站 DNS 端点安全组放行）"
  default     = "192.168.0.0/16"
}

variable "forwarding_rules" {
  type        = map(any)
  description = "出站 DNS 转发规则（域名 → 目标 DNS 服务器）"
  default = {
    "example-domain" = {
      domain_name = "example.com"
      target_ip   = ["1.1.1.1", "2.2.2.2"]
    }
    "test-domain" = {
      domain_name = "test.es"
      target_ip   = ["1.1.1.1"]
    }
  }
}
