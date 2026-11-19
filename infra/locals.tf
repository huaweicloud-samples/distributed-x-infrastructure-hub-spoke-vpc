# locals.tf — 本地配置：安全组规则 + 集中式 VPCEP 服务清单

locals {
  # 安全组：ECS 实例
  sg_instance = {
    name        = "instance_security_group"
    description = "ECS 实例安全组（放行 ICMP 与入站 SSH）"
    ingress = [
      {
        description = "ICMP"
        protocol    = "icmp"
        from_port   = 0
        to_port     = 0
        cidr        = "0.0.0.0/0"
      },
      {
        description = "SSH"
        protocol    = "tcp"
        from_port   = 22
        to_port     = 22
        cidr        = "10.0.0.0/8"
      },
    ]
    egress = [
      {
        description = "Any"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr        = "0.0.0.0/0"
      },
    ]
  }

  # 安全组：VPCEP
  sg_vpc_endpoints = {
    name        = "vpc_endpoints_sg"
    description = "VPC 终端节点安全组（放行 HTTPS 入站）"
    ingress = [
      {
        description = "HTTPS"
        protocol    = "tcp"
        from_port   = 443
        to_port     = 443
        cidr        = "0.0.0.0/0"
      },
    ]
    egress = [
      {
        description = "Any"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr        = "0.0.0.0/0"
      },
    ]
  }

  # 安全组：DNS 入站端点（混合 DNS）
  sg_dns_inbound = {
    name        = "dns_inbound_sg"
    description = "混合 DNS 入站端点安全组（仅放行本地数据中心 CIDR 的 DNS 流量）"
    ingress = [
      {
        description = "DNS over TCP"
        protocol    = "tcp"
        from_port   = 53
        to_port     = 53
        cidr        = var.on_premises_cidr
      },
      {
        description = "DNS over UDP"
        protocol    = "udp"
        from_port   = 53
        to_port     = 53
        cidr        = var.on_premises_cidr
      },
    ]
    egress = [
      {
        description = "Any"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr        = "0.0.0.0/0"
      },
    ]
  }

  # 安全组：DNS 出站端点
  sg_dns_outbound = {
    name        = "dns_outbound_sg"
    description = "混合 DNS 出站端点安全组"
    ingress = [
      {
        description = "DNS over TCP from VPC"
        protocol    = "tcp"
        from_port   = 53
        to_port     = 53
        cidr        = "0.0.0.0/0"
      },
      {
        description = "DNS over UDP from VPC"
        protocol    = "udp"
        from_port   = 53
        to_port     = 53
        cidr        = "0.0.0.0/0"
      },
    ]
    egress = [
      {
        description = "Any"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr        = "0.0.0.0/0"
      },
    ]
  }

  # 集中式 VPCEP 服务清单（共享服务 VPC 暴露给所有 spoke）
  endpoint_services = {
    obs = {
      service_name = "com.huaweicloud.cn-north-4.obs"
      zone_name    = "obs.cn-north-4.myhuaweicloud.com"
      record_names = ["", "*"]
      description  = "对象存储服务（OBS）私有终端节点"
    }
    smn = {
      service_name = "com.huaweicloud.cn-north-4.smn"
      zone_name    = "smn.cn-north-4.myhuaweicloud.com"
      record_names = [""]
      description  = "消息通知服务（SMN）私有终端节点"
    }
    ces = {
      service_name = "com.huaweicloud.cn-north-4.ces"
      zone_name    = "ces.cn-north-4.myhuaweicloud.com"
      record_names = [""]
      description  = "云监控服务（CES）私有终端节点"
    }
    dns = {
      service_name = "com.huaweicloud.cn-north-4.dns"
      zone_name    = "dns.cn-north-4.myhuaweicloud.com"
      record_names = [""]
      description  = "云解析服务（DNS）私有终端节点"
    }
  }
}
