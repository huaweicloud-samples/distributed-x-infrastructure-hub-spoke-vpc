# 架构说明（Architecture）

> 华为云 Hub-and-Spoke 网络架构：多 VPC 通过企业路由器互联，集中式服务 VPC 暴露 VPCEP 与 DNS。

## 1. 总体架构

本实践在华为云上构建一个 **Hub-and-Spoke 网络架构**，由以下核心组件组成：

- **企业路由器 ER（Enterprise Router）**：作为整个网络的「中心」，连接所有 VPC
- **共享服务 VPC（shared-services-vpc）**：中心化的「服务」承载者，部署 VPCEP + DNS Resolver + LTS 日志目标
- **Spoke VPC × N**：业务工作负载 VPC，每个包含 ECS 实例与 Flow Log
- **VPC 终端节点（VPCEP）**：从共享服务 VPC 暴露给所有 spoke，对接华为云原生服务（OBS / SMN / CES / DNS）
- **内网 DNS**：每个 VPCEP 服务对应一个 Private Zone，统一域名解析
- **混合 DNS**：出站 Resolver Rule 支持将指定域名解析请求转发到本地数据中心 DNS 服务器

## 2. 架构图

```
                    ┌────────────────────────────────────────┐
                    │   本地数据中心（on_premises_cidr）       │
                    │   DNS Server: 192.168.x.x                │
                    └──────────┬─────────────────────────────┘
                               │ (DNS query)
                               ▼
              ┌──────────────────────────────────────────┐
              │       共享服务 VPC（10.129.0.0/24）        │
              │  ┌─────────────────────────────────────┐ │
              │  │ VPCEP: OBS / SMN / CES / DNS         │ │
              │  │ DNS Private Zones × 4                │ │
              │  │ DNS Resolver Rule (出站转发)           │ │
              │  │ LTS 日志组 (VPC Flow Log 目标)        │ │
              │  └─────────────────────────────────────┘ │
              └────────────┬─────────────────────────────┘
                           │ (ER attachment)
                           ▼
              ┌──────────────────────────────────────────┐
              │   企业路由器 ER                          │
              │   - 路由表 rt-spoke                     │
              │   - 路由表 rt-shared-services           │
              │   - 传播关系 spoke ↔ shared-services    │
              └────────────┬─────────────────────────────┘
                           │ (ER attachment)
              ┌────────────┴─────────────┐
              ▼                          ▼
    ┌─────────────────────┐    ┌─────────────────────┐
    │ Spoke VPC-1 (10.0.0)│    │ Spoke VPC-2 (10.0.1)│
    │ ┌─────────────────┐ │    │ ┌─────────────────┐ │
    │ │ ECS × N (按 AZ) │ │    │ │ ECS × N (按 AZ) │ │
    │ └─────────────────┘ │    │ └─────────────────┘ │
    │ VPC Flow Log        │    │ VPC Flow Log        │
    └─────────────────────┘    └─────────────────────┘
```

## 3. 网络规划

| 网络单元 | CIDR | 备注 |
|---|---|---|
| shared-services-vpc | 10.129.0.0/24 | 共享服务 VPC |
| shared-services-vpc endpoints 子网 | /28（每 AZ） | 用于 VPCEP |
| shared-services-vpc transit 子网 | /28（每 AZ） | 用于 ER attachment |
| spoke-vpc-1 | 10.0.0.0/24 | 工作负载 VPC 1 |
| spoke-vpc-1 workload 子网 | /26（每 AZ） | ECS 工作负载 |
| spoke-vpc-1 transit 子网 | /28（每 AZ） | 用于 ER attachment |
| spoke-vpc-2 | 10.0.1.0/24 | 工作负载 VPC 2 |
| on_premises_cidr | 192.168.0.0/16 | 本地数据中心（用于入站 DNS SG 放行） |

**注意**：每个子网的 `gateway_ip` 由 `cidrhost(cidr, 1)` 计算（网段内第一个 IP）

## 4. 关键组件说明

### 4.1 企业路由器 ER

- 单实例部署，跨 2 个可用区
- ASN = 64512
- 两条路由表：
  - `rt-spoke`：关联所有 spoke attachments，学习 shared_services 路由
  - `rt-shared-services`：关联 shared_services attachment，学习 spoke 路由
- 通过 `huaweicloud_er_propagation` 自动学习路由
- 通过 `huaweicloud_er_static_route` 显式声明默认路由（0.0.0.0/0 → shared_services attachment）

### 4.2 VPCEP 服务集

| Service Key | service_name | 用途 | 内网域名 |
|---|---|---|---|
| obs | com.huaweicloud.cn-north-4.obs | 对象存储 | obs.cn-north-4.myhuaweicloud.com |
| smn | com.huaweicloud.cn-north-4.smn | 消息通知 | smn.cn-north-4.myhuaweicloud.com |
| ces | com.huaweicloud.cn-north-4.ces | 云监控 | ces.cn-north-4.myhuaweicloud.com |
| dns | com.huaweicloud.cn-north-4.dns | 云解析 | dns.cn-north-4.myhuaweicloud.com |

每个 service 对应：

- 1 个 `huaweicloud_vpcep_endpoint`
- 1 个 `huaweicloud_dns_zone`（private，关联所有 spoke + shared_services VPC）
- 多条 `huaweicloud_dns_recordset`（A 记录指向 VPCEP 内网 IP）

### 4.3 安全组

| SG 名 | 用途 | 关键规则 |
|---|---|---|
| `instance_security_group` | ECS 实例 | 入站：ICMP + SSH (10.0.0.0/8)；出站：全部 |
| `endpoints_sg` | VPCEP | 入站：HTTPS；出站：全部 |
| `dns_inbound_sg` | DNS 入站端点 | 入站：53/tcp + 53/udp（仅 on_premises_cidr） |
| `dns_outbound_sg` | DNS 出站端点 | 入站：53/tcp + 53/udp（0.0.0.0/0） |

### 4.4 混合 DNS

- **入站**：本地数据中心 DNS 服务器（on_premises_cidr）向 shared services VPC 内自建 DNS 实例发起查询
  - 自建 DNS 实例（BIND / CoreDNS）部署在 endpoints 子网内
  - `dns_inbound_sg` 放行 on_premises_cidr 的 53/tcp + 53/udp
- **出站**：`huaweicloud_dns_resolver_rule.outbound` 将 `var.forwarding_rules` 中配置的域名解析请求转发到本地数据中心 DNS 服务器
  - 当前 endpoint_id 是占位（指向 secgroup），apply 前需替换为自建 DNS 端点 ID

### 4.5 IAM 委托

- ECS 实例通过 `agency_name` 字段绑定委托 `${var.identifier}-ecs-agency`
- 委托域 `op_svc_ces`
- 项目角色：`CES FullAccess` + `OBS ReadOnlyAccess`

### 4.6 KMS + LTS 日志加密

- KMS Key `${var.identifier}-log-key`，pending_days = 7
- LTS Group `${var.identifier}-flow-log` 接收所有 VPC 的 Flow Log
- 每个 VPC 启用 flow log（traffic_type = "all"），发到同一 LTS Group

## 5. ECS 部署

- 每个 spoke VPC 内每个 AZ 部署 1 台 ECS 实例
- 默认规格 `s6.small.1`
- 默认镜像 `CentOS 7.9 64bit`（公共镜像）
- 系统盘 GPSSD 40GB
- 绑定 `instance_security_group`
- 绑定 `${identifier}-ecs-agency` 委托

## 6. 已知限制

- 华为云 `huaweicloud_networking_secgroup_rule` 不支持 `protocol = "-1"`，本实践中「出站全部放行」类规则省略 `protocol` 字段
- 华为云 `huaweicloud_dns_recordset` 不支持 alias 记录类型，统一改为 A 记录指向 VPCEP 内网 IP
- 自建 DNS 实例（BIND / CoreDNS）的部署不在本 IaC 范围，需用户自行部署
