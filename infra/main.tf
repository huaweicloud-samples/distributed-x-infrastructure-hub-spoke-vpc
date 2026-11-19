# main.tf — Hub-and-Spoke 网络编排

# ============================================================================
# 可用区与镜像数据源
# ============================================================================

data "huaweicloud_availability_zones" "current" {
  region = var.region
}

# 共享镜像（按 name 过滤公共镜像，跨 spoke 复用）
data "huaweicloud_images_image" "centos" {
  name        = "CentOS 7.9 64bit"
  most_recent = true
  visibility  = "public"
}

# ============================================================================
# KMS 密钥（日志加密）
# ============================================================================

resource "huaweicloud_kms_key" "log_key" {
  key_alias    = "${var.identifier}-log-key"
  pending_days = "7"
  is_enabled   = true
}

# ============================================================================
# LTS 日志组与日志流（VPC Flow Log 目标）
# ============================================================================

resource "huaweicloud_lts_group" "flow_log" {
  group_name  = "${var.identifier}-flow-log"
  ttl_in_days = 7
}

resource "huaweicloud_lts_stream" "flow_log" {
  group_id    = huaweicloud_lts_group.flow_log.id
  stream_name = "${var.identifier}-flow-log-stream"
  ttl_in_days = 7
}

# ============================================================================
# 企业路由器 ER（中转连接所有 VPC）
# ============================================================================

resource "huaweicloud_er_instance" "main" {
  region             = var.region
  availability_zones = slice(data.huaweicloud_availability_zones.current.names, 0, 2)
  name               = "er-${var.identifier}"
  asn                = 64512
  description        = "Enterprise Router for hub-and-spoke topology"
}

# 路由表：spoke 路由表
resource "huaweicloud_er_route_table" "spoke" {
  instance_id = huaweicloud_er_instance.main.id
  name        = "rt-spoke-${var.identifier}"
  description = "Propagates spoke VPC attachments"
}

# 路由表：共享服务路由表
resource "huaweicloud_er_route_table" "shared_services" {
  instance_id = huaweicloud_er_instance.main.id
  name        = "rt-shared-services-${var.identifier}"
  description = "Propagates shared-services VPC attachment"
}

# ============================================================================
# 共享服务 VPC
# ============================================================================

resource "huaweicloud_vpc" "shared_services" {
  name = "shared-services-vpc-${var.identifier}"
  cidr = var.shared_services_vpc.cidr_block
}

# 共享服务 VPC：终端节点子网（每个 AZ 一个）
resource "huaweicloud_vpc_subnet" "shared_services_endpoints" {
  for_each = {
    for idx, az in slice(var.availability_zones, 0, var.shared_services_vpc.number_azs) :
    az => idx
  }

  vpc_id            = huaweicloud_vpc.shared_services.id
  name              = "shared-services-endpoints-${each.key}"
  cidr              = cidrsubnet(var.shared_services_vpc.cidr_block, var.shared_services_vpc.endpoints_subnet_netmask - (32 - tonumber(split("/", var.shared_services_vpc.cidr_block)[1])), each.value)
  gateway_ip        = cidrhost(cidrsubnet(var.shared_services_vpc.cidr_block, var.shared_services_vpc.endpoints_subnet_netmask - (32 - tonumber(split("/", var.shared_services_vpc.cidr_block)[1])), each.value), 1)
  availability_zone = each.key
}

# 共享服务 VPC：中转子网（用于 ER attachment）
resource "huaweicloud_vpc_subnet" "shared_services_transit" {
  for_each = {
    for idx, az in slice(var.availability_zones, 0, var.shared_services_vpc.number_azs) :
    az => idx
  }

  vpc_id            = huaweicloud_vpc.shared_services.id
  name              = "shared-services-transit-${each.key}"
  cidr              = cidrsubnet(var.shared_services_vpc.cidr_block, var.shared_services_vpc.transit_subnet_netmask - (32 - tonumber(split("/", var.shared_services_vpc.cidr_block)[1])), each.value + 8)
  gateway_ip        = cidrhost(cidrsubnet(var.shared_services_vpc.cidr_block, var.shared_services_vpc.transit_subnet_netmask - (32 - tonumber(split("/", var.shared_services_vpc.cidr_block)[1])), each.value + 8), 1)
  availability_zone = each.key
}

# 共享服务 VPC：VPC Flow Log
resource "huaweicloud_vpc_flow_log" "shared_services" {
  name          = "fl-shared-services-${var.identifier}"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.shared_services.id
  log_group_id  = huaweicloud_lts_group.flow_log.id
  log_stream_id = huaweicloud_lts_stream.flow_log.id
  traffic_type  = "all"
  enabled       = true
}

# 共享服务 VPC：连接企业路由器
resource "huaweicloud_er_vpc_attachment" "shared_services" {
  instance_id = huaweicloud_er_instance.main.id
  vpc_id      = huaweicloud_vpc.shared_services.id
  subnet_id   = huaweicloud_vpc_subnet.shared_services_transit[var.availability_zones[0]].id
  name        = "att-shared-services-${var.identifier}"
  description = "Attachment of shared services VPC"
}

# 共享服务路由表关联 shared-services attachment
resource "huaweicloud_er_association" "shared_services" {
  instance_id    = huaweicloud_er_instance.main.id
  route_table_id = huaweicloud_er_route_table.shared_services.id
  attachment_id  = huaweicloud_er_vpc_attachment.shared_services.id
}

# ============================================================================
# Spoke VPC（for_each 模式）
# ============================================================================

resource "huaweicloud_vpc" "spoke" {
  for_each = var.vpcs

  name = "${each.key}-${var.identifier}"
  cidr = each.value.cidr_block
}

# Spoke VPC：工作负载子网
resource "huaweicloud_vpc_subnet" "spoke_workload" {
  for_each = {
    for vpc_key, vpc_cfg in var.vpcs :
    vpc_key => {
      for idx in range(vpc_cfg.number_azs) :
      "${vpc_key}-${idx}" => {
        cidr = vpc_cfg.workload_subnets[idx]
        az   = var.availability_zones[idx]
      }
    }
  }

  vpc_id            = huaweicloud_vpc.spoke[split("-", each.key)[0]].id
  name              = "workload-${each.key}"
  cidr              = each.value.cidr
  gateway_ip        = cidrhost(each.value.cidr, 1)
  availability_zone = each.value.az
}

# Spoke VPC：中转子网
resource "huaweicloud_vpc_subnet" "spoke_transit" {
  for_each = {
    for vpc_key, vpc_cfg in var.vpcs :
    vpc_key => {
      for idx in range(vpc_cfg.number_azs) :
      "${vpc_key}-${idx}" => {
        cidr = vpc_cfg.transit_subnets[idx]
        az   = var.availability_zones[idx]
      }
    }
  }

  vpc_id            = huaweicloud_vpc.spoke[split("-", each.key)[0]].id
  name              = "transit-${each.key}"
  cidr              = each.value.cidr
  gateway_ip        = cidrhost(each.value.cidr, 1)
  availability_zone = each.value.az
}

# Spoke VPC：VPC Flow Log
resource "huaweicloud_vpc_flow_log" "spoke" {
  for_each = huaweicloud_vpc.spoke

  name          = "fl-${each.key}-${var.identifier}"
  resource_type = "vpc"
  resource_id   = each.value.id
  log_group_id  = huaweicloud_lts_group.flow_log.id
  log_stream_id = huaweicloud_lts_stream.flow_log.id
  traffic_type  = "all"
  enabled       = true
}

# Spoke VPC：连接企业路由器
resource "huaweicloud_er_vpc_attachment" "spoke" {
  for_each = huaweicloud_vpc.spoke

  instance_id = huaweicloud_er_instance.main.id
  vpc_id      = each.value.id
  subnet_id   = huaweicloud_vpc_subnet.spoke_transit["${each.key}-0"].id

  name        = "att-${each.key}-${var.identifier}"
  description = "Attachment of ${each.key} spoke VPC"
}

# Spoke 路由表关联 spoke attachments
resource "huaweicloud_er_association" "spoke" {
  for_each = huaweicloud_er_vpc_attachment.spoke

  instance_id    = huaweicloud_er_instance.main.id
  route_table_id = huaweicloud_er_route_table.spoke.id
  attachment_id  = each.value.id
}

# ER 传播：shared_services 路由表学习 spoke 路由
resource "huaweicloud_er_propagation" "spoke_to_shared_services" {
  for_each = huaweicloud_er_vpc_attachment.spoke

  instance_id    = huaweicloud_er_instance.main.id
  route_table_id = huaweicloud_er_route_table.shared_services.id
  attachment_id  = each.value.id
}

# ER 传播：spoke 路由表学习 shared_services 路由
resource "huaweicloud_er_propagation" "shared_services_to_spoke" {
  instance_id    = huaweicloud_er_instance.main.id
  route_table_id = huaweicloud_er_route_table.spoke.id
  attachment_id  = huaweicloud_er_vpc_attachment.shared_services.id
}

# ============================================================================
# 静态路由：每个 spoke 通过 shared_services 访问默认路径
# ============================================================================

resource "huaweicloud_er_static_route" "spoke_default" {
  for_each = huaweicloud_er_vpc_attachment.spoke

  route_table_id = huaweicloud_er_route_table.spoke.id
  destination    = "0.0.0.0/0"
  attachment_id  = huaweicloud_er_vpc_attachment.shared_services.id
}

resource "huaweicloud_er_static_route" "shared_services_default" {
  route_table_id = huaweicloud_er_route_table.shared_services.id
  destination    = "0.0.0.0/0"
  attachment_id  = huaweicloud_er_vpc_attachment.shared_services.id
}

# ============================================================================
# VPC 终端节点（共享服务 VPC 集中暴露）
# ============================================================================
# service_id 由 data 源查询；查询失败时由用户手动替换为真实 service_id。

data "huaweicloud_vpcep_services" "available" {}

resource "huaweicloud_vpcep_endpoint" "shared" {
  for_each = local.endpoint_services

  service_id = try([
    for s in data.huaweicloud_vpcep_services.available.endpoint_services : s.id
    if s.service_name == each.value.service_name
  ][0], null)

  vpc_id      = huaweicloud_vpc.shared_services.id
  network_id  = huaweicloud_vpc_subnet.shared_services_endpoints[var.availability_zones[0]].id
  enable_dns  = true
  description = each.value.description

  lifecycle {
    ignore_changes = [service_id]
  }
}

# ============================================================================
# VPCEP 安全组（放行 443）
# ============================================================================

resource "huaweicloud_networking_secgroup" "vpc_endpoints" {
  name        = local.sg_vpc_endpoints.name
  description = local.sg_vpc_endpoints.description
}

resource "huaweicloud_networking_secgroup_rule" "vpc_endpoints_ingress" {
  for_each = { for idx, rule in local.sg_vpc_endpoints.ingress : idx => rule }

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.from_port
  port_range_max    = each.value.to_port
  remote_ip_prefix  = each.value.cidr
  security_group_id = huaweicloud_networking_secgroup.vpc_endpoints.id
}

resource "huaweicloud_networking_secgroup_rule" "vpc_endpoints_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.vpc_endpoints.id
}

# ============================================================================
# 实例安全组（按 spoke 划分）
# ============================================================================

resource "huaweicloud_networking_secgroup" "spoke" {
  for_each = huaweicloud_vpc.spoke

  name        = "${local.sg_instance.name}-${each.key}"
  description = local.sg_instance.description
}

resource "huaweicloud_networking_secgroup_rule" "spoke_ingress" {
  for_each = {
    for vpc_key in keys(huaweicloud_networking_secgroup.spoke) :
    vpc_key => {
      for idx, rule in local.sg_instance.ingress :
      "${vpc_key}-${idx}" => {
        sg_id = huaweicloud_networking_secgroup.spoke[vpc_key].id
        rule  = rule
      }
    }
  }

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.rule.protocol
  port_range_min    = each.value.rule.from_port
  port_range_max    = each.value.rule.to_port
  remote_ip_prefix  = each.value.rule.cidr
  security_group_id = each.value.sg_id
}

resource "huaweicloud_networking_secgroup_rule" "spoke_egress" {
  for_each = huaweicloud_networking_secgroup.spoke

  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = each.value.id
}

# ============================================================================
# DNS：入站 / 出站安全组
# ============================================================================

resource "huaweicloud_networking_secgroup" "dns_inbound" {
  name        = local.sg_dns_inbound.name
  description = local.sg_dns_inbound.description
}

resource "huaweicloud_networking_secgroup_rule" "dns_inbound_ingress" {
  for_each = { for idx, rule in local.sg_dns_inbound.ingress : idx => rule }

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.from_port
  port_range_max    = each.value.to_port
  remote_ip_prefix  = each.value.cidr
  security_group_id = huaweicloud_networking_secgroup.dns_inbound.id
}

resource "huaweicloud_networking_secgroup_rule" "dns_inbound_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.dns_inbound.id
}

resource "huaweicloud_networking_secgroup" "dns_outbound" {
  name        = local.sg_dns_outbound.name
  description = local.sg_dns_outbound.description
}

resource "huaweicloud_networking_secgroup_rule" "dns_outbound_ingress" {
  for_each = { for idx, rule in local.sg_dns_outbound.ingress : idx => rule }

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.from_port
  port_range_max    = each.value.to_port
  remote_ip_prefix  = each.value.cidr
  security_group_id = huaweicloud_networking_secgroup.dns_outbound.id
}

resource "huaweicloud_networking_secgroup_rule" "dns_outbound_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.dns_outbound.id
}

# ============================================================================
# 混合 DNS：出站 DNS 转发规则
# ============================================================================
# 注：huaweicloud_dns_resolver_rule 用于将 VPC 内 DNS 查询转发到指定 IP。
# 允许本地数据中心 DNS 向云端转发的能力在华为云上无原生资源，
# 实施方式：在共享服务 VPC 部署自建 BIND / CoreDNS 实例（监听 endpoints 子网内的 53 端口），
# 由本地数据中心的 DNS 转发器向其转发查询；自建部分不在本 IaC 范围。
# 出站 DNS Resolver Rule 中的 endpoint_id 指向 shared services VPC 中自建 DNS 的 ID。

resource "huaweicloud_dns_resolver_rule" "outbound" {
  for_each = var.forwarding_rules

  name        = "${each.key}-${var.identifier}"
  domain_name = each.value.domain_name

  # 占位 endpoint_id（指向共享服务 VPC 中自建 DNS；apply 前替换为真实 ID）
  endpoint_id = huaweicloud_networking_secgroup.vpc_endpoints.id

  dynamic "ip_addresses" {
    for_each = each.value.target_ip
    content {
      ip = ip_addresses.value
    }
  }
}

# ============================================================================
# DNS 内网域名与记录集（每个 endpoint service 对应一个 zone）
# ============================================================================

resource "huaweicloud_dns_zone" "endpoint" {
  for_each = local.endpoint_services

  name        = each.value.zone_name
  description = "Private zone for ${each.key} VPC endpoint"
  zone_type   = "private"

  router {
    router_id = huaweicloud_vpc.shared_services.id
  }
  dynamic "router" {
    for_each = huaweicloud_vpc.spoke
    content {
      router_id = router.value.id
    }
  }
}

# 模块：DNS 记录集（针对单个 VPCEP 的多个 alias name）
module "endpoint_record" {
  source = "./modules/dns_record"

  for_each = local.endpoint_services

  zone_id      = huaweicloud_dns_zone.endpoint[each.key].id
  zone_name    = each.value.zone_name
  endpoint_ips = huaweicloud_vpcep_endpoint.shared[each.key].dns_names
  record_names = each.value.record_names
}

# ============================================================================
# IAM：ECS 实例委托（用于云监控 / 云运维等云服务访问）
# ============================================================================

resource "huaweicloud_identity_agency" "ecs" {
  name                  = "${var.identifier}-ecs-agency"
  description           = "Agency granting ECS instances access to OBS (read-only) and CES"
  duration              = "FOREVER"
  delegated_domain_name = "op_svc_ces"

  project_role {
    project = var.region
    roles = [
      "CES FullAccess",
      "OBS ReadOnlyAccess",
    ]
  }
}

# ============================================================================
# ECS 实例（每个 spoke 内的每个 AZ 一个）
# ============================================================================

module "compute" {
  source = "./modules/compute"

  for_each = huaweicloud_vpc.spoke

  identifier        = var.identifier
  vpc_name          = each.key
  vpc_id            = each.value.id
  workload_subnets  = [for idx in range(var.vpcs[each.key].number_azs) : huaweicloud_vpc_subnet.spoke_workload["${each.key}-${idx}"].id]
  number_azs        = var.vpcs[each.key].number_azs
  flavor_id         = var.vpcs[each.key].instance_flavor
  image_id          = data.huaweicloud_images_image.centos.id
  security_group_id = huaweicloud_networking_secgroup.spoke[each.key].id
  agency_name       = huaweicloud_identity_agency.ecs.name
}
