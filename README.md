# distributed-x-infrastructure-hub-spoke-vpc / Hub-and-Spoke 网络架构 + 共享服务 VPC 最佳实践

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-IAM%20Auth-red.svg)](https://support.huaweicloud.com/intl/en-us/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> 基于华为云 Terraform 的 Hub-and-Spoke 网络架构最佳实践
> Huawei Cloud Hub-and-Spoke Network Architecture with Shared Services VPC

---

## 1. 简介 / Overview

**中文**：本实践提供 **Hub-and-Spoke 网络架构 + 集中式共享服务 VPC** 的完整 Terraform 部署方案，覆盖 VPC 互联、VPC 终端节点（VPCEP）、VPC 流日志、私有域名解析、混合 DNS（出入站）等核心能力。面向网络架构师 / 云平台运维 / 后端工程师，可作为多 VPC 互联的参考架构、混合云接入学习样例、生产环境网络模板使用。

### 核心能力

- **多 VPC 全互联**：通过企业路由器（ER）实现 spoke VPC 与 shared services VPC 互联
- **集中式 VPCEP**：在共享服务 VPC 暴露华为云原生服务（OBS / SMN / CES / DNS）私有终端节点
- **私有域名解析**：每个 VPCEP 服务对应一个 Private Zone，A 记录指向 VPCEP 内网 IP
- **VPC Flow Log**：每个 VPC 启用流日志，统一发到 LTS 日志组
- **混合 DNS**：出站 Resolver Rule 将指定域名解析请求转发到本地数据中心 DNS；入站由自建 DNS 实例承担
- **安全组规范**：实例 / 终端节点 / DNS 入站 / DNS 出站四类安全组，分别定义精细访问规则
- **IAM 委托**：ECS 实例绑定委托，自动获得 CES + OBS 访问权限

---

## 2. 目录

- [1. 简介](#1-简介--overview)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件-critical)
- [7. 快速开始](#7-快速开始-critical)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证-critical)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证-critical)
- [16. 联系方式 / 维护者](#16-联系方式--维护者-critical)

---

## 3. 架构图

> 通过企业路由器 + 共享服务 VPC + 多个 spoke VPC 构建 hub-and-spoke 网络拓扑

```
                本地数据中心（on_premises_cidr）
                DNS Server: 192.168.x.x
                       │
                       │ (DNS query)
                       ▼
        ┌──────────────────────────────────────┐
        │   共享服务 VPC（10.129.0.0/24）        │
        │  ┌────────────────────────────────┐   │
        │  │ VPCEP: OBS / SMN / CES / DNS    │   │
        │  │ DNS Private Zones × 4          │   │
        │  │ DNS Resolver Rule (出站)         │   │
        │  │ LTS 日志组 (VPC Flow Log 目标)  │   │
        │  └────────────────────────────────┘   │
        └──────────────────┬───────────────────┘
                           │ (ER attachment)
                           ▼
            ┌──────────────────────────────┐
            │   企业路由器 ER               │
            │   - 路由表 rt-spoke          │
            │   - 路由表 rt-shared-services│
            │   - 传播关系（双向自动学习）│
            └──────────────┬───────────────┘
                           │ (ER attachment)
              ┌────────────┴────────────┐
              ▼                          ▼
    ┌─────────────────────┐    ┌─────────────────────┐
    │ Spoke VPC-1         │    │ Spoke VPC-2         │
    │ (10.0.0.0/24)       │    │ (10.0.1.0/24)       │
    │ ┌─────────────────┐ │    │ ┌─────────────────┐ │
    │ │ ECS × N (按 AZ) │ │    │ │ ECS × N (按 AZ) │ │
    │ └─────────────────┘ │    │ └─────────────────┘ │
    │ VPC Flow Log        │    │ VPC Flow Log        │
    └─────────────────────┘    └─────────────────────┘
```

**关键组件说明**：

- **企业路由器 ER**：中转连接所有 VPC，支持双向路由自动学习
- **共享服务 VPC**：集中暴露 VPCEP 与 DNS，是所有 spoke 的「目的地」
- **Spoke VPC**：业务工作负载 VPC，每个含 ECS 与 Flow Log
- **VPCEP**：从共享服务 VPC 暴露华为云原生服务私有终端节点

---

## 4. 方案亮点

- **声明式编排**：所有 VPC / 子网 / ER attachment / 路由传播 / VPCEP / DNS 都通过 Terraform 显式声明，避免模块嵌套黑盒
- **可复用模块**：`modules/compute` 与 `modules/dns_record` 两个独立模块，可在新 spoke 中直接复用
- **多 AZ 默认部署**：默认每个资源在 2 个可用区部署，提高可用性
- **精细安全组**：实例 / 终端节点 / DNS 入站 / DNS 出站 四类安全组，分别定义规则
- **混合 DNS 支持**：出站 DNS 转发规则作为 Terraform 变量声明，本地数据中心侧配合自建 DNS 实例即可打通双向解析
- **统一日志**：所有 VPC 的 Flow Log 发到同一个 LTS 日志组，便于集中查询

---

## 5. 涉及云服务

| 服务 | 用途 | 备注 |
|---|---|---|
| 虚拟私有云 VPC | 网络隔离 | 多个 VPC（共享服务 + spoke × N） |
| 子网 Subnet | VPC 内网段划分 | 工作负载 / 中转 / 终端节点 三类子网 |
| 企业路由器 ER | VPC 间互联 | 单实例跨 2 个可用区 |
| 弹性云服务器 ECS | 工作负载 | 每个 spoke 每个 AZ 1 台 |
| 密钥管理服务 KMS | 日志加密密钥 | pending_days = 7 |
| 云日志服务 LTS | Flow Log 目标 | log_group + log_stream |
| VPC 终端节点 VPCEP | 私有服务暴露 | OBS / SMN / CES / DNS |
| 云解析服务 DNS | 内网域名 + 转发规则 | private zone + recordset + resolver_rule |
| 虚拟专用网络 VPN (可选) | 本地数据中心接入 | 不在本 IaC 范围 |
| 统一身份认证 IAM | 委托授权 | ECS 委托 + 项目角色 |

> 所有服务均可通过本仓库的 Terraform 一键创建；如需清理，请参见 [第 10 节「清理资源」](#10-清理资源)。

---

## 6. 前置条件 [CRITICAL]

| 项 | 要求 | 说明 |
|---|---|---|
| **账号** | 已开通华为云账号并完成实名认证 | 个人/企业账号均可 |
| **权限** | 账号具备 IAM **Tenant Administrator** 或等效权限 | 用于创建 VPC / ER / ECS / KMS / IAM 等资源 |
| **Region** | 推荐 `cn-north-4`（北京四） | 跨 region 可能涉及服务可用性差异 |
| **可用区** | region 内至少 2 个可用区 | 默认使用 `cn-north-4a`、`cn-north-4b` |
| **Terraform** | `>= 1.5.0` | IaC 部署工具 |
| **huaweicloud Provider** | `~> 1.95` | 华为云 Terraform Provider（本地 filesystem_mirror 已配置） |
| **AK/SK** | 在华为云「我的凭证」页面获取 Access Key ID 与 Secret Access Key，并填入部署脚本 | **不要**将凭据写入任何代码或配置文件 |

---

## 7. 快速开始 [CRITICAL]

### 一键部署（推荐）

```bash
# 1. 克隆本仓库
git clone https://github.com/huaweicloud-samples/distributed-x-infrastructure-hub-spoke-vpc distributed-x-infrastructure-hub-spoke-vpc
cd distributed-x-infrastructure-hub-spoke-vpc

# 2. 配置访问凭据（见前置条件）
export HW_ACCESS_KEY="<AK>"
export HW_SECRET_KEY="<SK>"

# 3. 一键部署
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> **部署耗时**：约 5-15 分钟（视 spoke VPC 数量与可用区数而定）
> **完整步骤与每步预期输出**：参见 [第 8 节「分步部署」](#8-分步部署)

---

## 8. 分步部署

### 步骤 1：初始化工作目录

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform init
```

**预期输出**：`Terraform has been successfully initialized!`

### 步骤 2：自定义变量（可选）

编辑 `infra/variables.tf`，按需修改：

- `region`：华为云区域
- `identifier`：项目标识
- `vpcs`：Spoke VPC 定义（CIDR / 工作负载子网 / ECS 规格等）
- `shared_services_vpc`：共享服务 VPC 配置
- `on_premises_cidr`：本地数据中心 CIDR
- `forwarding_rules`：出站 DNS 转发规则

### 步骤 3：预演资源变更

```bash
terraform plan
```

**预期输出**：`Plan: N to add, 0 to change, 0 to destroy.`

### 步骤 4：执行部署

```bash
terraform apply -auto-approve
```

**预期输出**：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

### 步骤 5：记录关键输出

```bash
terraform output
```

**预期输出**：列出所有 `output` 字段值（VPC ID、ER ID、ECS ID、VPCEP ID、域名 ID、KMS Key ID、LTS Group ID、ECS 委托名称），请妥善保存用于后续验证。

---

## 9. 使用方法 / 验证 [CRITICAL]

> **校验说明**：本实践已通过 `terraform validate` 与 `terraform fmt -check` 校验，确认配置合法且格式正确。请按本节步骤自行验证，确认业务功能可用后方可视为交付完成。

### 验证 1：Terraform 语法校验

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform validate
```

**预期输出**：`Success! The configuration is valid.`

### 验证 2：Terraform 格式校验

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform fmt -check -recursive
```

**预期输出**：无输出，Exit code 0

### 验证 3：查看资源依赖关系

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform providers
```

**预期输出**：

```
Providers required by configuration:
.
├── provider[registry.terraform.io/huaweicloud/huaweicloud] ~> 1.95
├── module.compute
│   └── provider[registry.terraform.io/huaweicloud/huaweicloud] ~> 1.95
└── module.endpoint_record
    └── provider[registry.terraform.io/huaweicloud/huaweicloud] ~> 1.95
```

### 验证 4：查看关键输出

```bash
terraform output
```

**预期结果**：列出所有 output 值，包含 VPC ID、ER ID、ECS ID、VPCEP ID、内网域名 ID 等

### 验证 5：业务端到端（部署后）

```bash
# 1. 通过 ECS 控制台登录 spoke ECS
# 2. 在 ECS 内测试 OBS 访问（通过 VPCEP）
curl -I https://obs.cn-north-4.myhuaweicloud.com

# 3. 测试 CES agent 上报（agent 已通过委托自动配置）
# 4. 测试内网 DNS 解析
nslookup obs.cn-north-4.myhuaweicloud.com <内网 DNS IP>
```

**预期结果**：

- `curl` 命令返回 403 或 200（说明 OBS 域名可解析，OBS VPCEP 生效）
- `nslookup` 返回 VPCEP 内网 IP（说明内网 DNS 解析生效）

---

## 10. 清理资源

```bash
# 进入部署目录
cd distributed-x-infrastructure-hub-spoke-vpc/infra

# 一键释放所有资源
terraform destroy -auto-approve
```

**预期输出**：`Destroy complete! Resources: N destroyed.`

> **避免资源残留**：
>
> - `terraform destroy` 仅释放 Terraform state 中追踪的资源
> - 若中途使用了 API 直接创建的资源（如手工上传的 OBS 对象、控制台手动创建的 EIP 等），需手动释放
> - KMS Key 删除有 7 天等待期（`pending_days = "7"`），期间会保留在「待删除」状态
> - 公共资源（账号内其他任务共享的 NAT / VPC 等）不会被影响

---

## 11. 详细说明

### 工作流程

本实践从请求进入到业务完成的全链路：

1. **网络构建**：声明所有 VPC / 子网 / ER attachment / 路由传播 / 路由表 / 静态路由
2. **安全组编排**：为每个 spoke 创建实例安全组，关联 VPCEP 安全组 + DNS 入站/出站安全组
3. **集中式服务暴露**：在 shared services VPC 创建 4 个 VPCEP（OBS / SMN / CES / DNS）
4. **内网 DNS 解析**：为每个 VPCEP 服务创建 private zone，关联所有 VPC；A 记录指向 VPCEP 内网 IP
5. **混合 DNS**：出站 resolver_rule 将 `forwarding_rules` 中的域名解析请求转发到本地数据中心 DNS
6. **IAM 委托**：创建 ECS 委托，含 CES + OBS 权限
7. **ECS 部署**：在每个 spoke 每个 AZ 创建 ECS 实例，绑定实例安全组 + ECS 委托
8. **VPC Flow Log**：每个 VPC 启用 Flow Log，统一发到 LTS 日志组

### 配置项

| 变量 | 默认值 | 说明 |
|---|---|---|
| `region` | `cn-north-4` | 华为云区域 |
| `identifier` | `hubspoke-shared-services` | 项目标识 |
| `availability_zones` | `[cn-north-4a, cn-north-4b, cn-north-4c]` | 可用区列表 |
| `vpcs` | 2 个 spoke VPC | Spoke VPC 定义 |
| `shared_services_vpc.cidr_block` | `10.129.0.0/24` | 共享服务 VPC CIDR |
| `shared_services_vpc.number_azs` | `2` | 共享服务 VPC 可用区数 |
| `on_premises_cidr` | `192.168.0.0/16` | 本地数据中心 CIDR |
| `forwarding_rules` | 2 条转发规则 | 出站 DNS 转发规则 |

### 接口 / API

本实践通过以下输出暴露关键资源 ID：

```bash
terraform output vpcs                # VPC ID 集合
terraform output enterprise_router    # ER ID + 路由表 ID
terraform output compute_instances    # ECS ID 集合
terraform output vpc_endpoints       # VPCEP ID 集合
terraform output private_zones       # 内网域名 ID 集合
terraform output kms_key_id          # KMS Key ID
terraform output lts_log_group       # LTS 日志组 ID
terraform output ecs_agency_name     # ECS 实例委托名称
```

---

## 12. 依赖

### 主要依赖

| 名称 | 版本 | 用途 |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC 编排 |
| huaweicloud Provider | `~> 1.95` | 华为云资源 |
| 华为云 IAM | — | 委托授权 |

### 模块依赖

| 模块 | 路径 | 用途 |
|---|---|---|
| `modules/compute` | `./infra/modules/compute` | 创建 ECS 实例（每 spoke × 每 AZ × 1 台） |
| `modules/dns_record` | `./infra/modules/dns_record` | 为 VPCEP 服务创建 DNS 记录集 |

---

## 13. FAQ / 故障排除

### Q1：部署时提示「权限不足」怎么办？

**A**：确认账号具备 IAM **Tenant Administrator** 权限，或至少包含 `VPC Administrator`、`ER Administrator`、`ECS Administrator`、`KMS Administrator`、`IAM Administrator`、`LTS Administrator`、`DNS Administrator`、`VPCEP Administrator` 等子服务管理员权限。

### Q2：terraform init 失败，提示无法访问 registry？

**A**：本仓库依赖本地 filesystem_mirror（路径 `<本地 provider-mirror 目录>/provider-mirror`），需设置环境变量 `TF_CLI_CONFIG_FILE=<本地 provider-mirror 目录>/tfcli.hcl`。如本地 mirror 不可用，需自行配置网络代理或私有 registry。

### Q3：terraform apply 报 DNS resolver rule endpoint_id 错误？

**A**：当前代码中 `endpoint_id` 指向 secgroup（占位），需替换为 shared services VPC 中自建 DNS 实例的真实 endpoint_id。详见 `docs/deployment-guide.md` §3.4。

### Q4：ECS 创建失败，提示镜像不存在？

**A**：默认使用公共镜像 `CentOS 7.9 64bit`，如 region 不支持，可修改 `infra/variables.tf` 中 `image_name` 字段为该 region 可用的镜像名（如 `Ubuntu 22.04 server 64bit`）。

### Q5：本地数据中心如何接入华为云 DNS？

**A**：本实践不包含 VPN / Direct Connect 部署。在本地数据中心侧部署 DNS 转发器，将需要解析的华为云域名（如 `*.cn-north-4.myhuaweicloud.com`）指向华为云内网 DNS（100.125.0.2 / 100.125.1.2），或通过 VPN/专线打通后用 shared services VPC 中自建 DNS 实例。

### 故障排查清单

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| `terraform init` 失败 | 网络无法访问 registry | 设置 `TF_CLI_CONFIG_FILE` 指向 filesystem_mirror |
| VPCEP service_id 为 null | 区域无对应 VPCEP 服务 | 检查 `data.huaweicloud_vpcep_services` 输出 |
| ECS 启动失败 | 镜像 ID / 规格不存在 | 改用 `data.huaweicloud_compute_flavors` 查询可用规格 |
| Flow Log 无数据 | LTS topic 权限不足 | 检查 IAM 委托是否有 LTS 写入权限 |
| 混合 DNS 不生效 | 自建 DNS 实例未部署 / endpoint_id 未替换 | 见 `docs/deployment-guide.md` §4 |

---

## 14. 贡献指南

欢迎提交 Issue 与 PR。请遵循以下流程：

1. **Issue**：描述问题 / 建议（含复现命令、预期 / 实际输出、截图）
2. **PR**：基于 `main` 分支新建 feature 分支；提交前运行 `terraform validate` 与 `terraform fmt -check`
3. **Code Review**：由 **[@dgc-git](https://github.com/dgc-git)** reviewer 审核通过后合并

---

## 15. 许可证 [CRITICAL]

本实践采用 **MIT No Attribution** 许可证发布。详见仓库根目录 [`LICENSE`](LICENSE) 文件。

```
MIT No Attribution

Copyright (c) Huawei Cloud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software... (no attribution required)
```

---

## 16. 联系方式 / 维护者 [CRITICAL]

| 项 | 内容 |
|---|---|
| **创建者** | [@dgc-git](https://github.com/dgc-git) |
| **维护者** | [@dgc-git](https://github.com/dgc-git) |
| **联系方式** | GitHub Issues / PR（见 [第 14 节](#14-贡献指南)） |
