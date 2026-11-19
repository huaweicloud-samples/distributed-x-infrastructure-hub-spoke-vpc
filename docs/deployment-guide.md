# 部署指导书（Deployment Guide）

> 在华为云上部署本实践的完整步骤。

## 1. 前置条件

| 项 | 要求 |
|---|---|
| 华为云账号 | 已开通并完成实名认证 |
| IAM 权限 | Tenant Administrator 或等效权限 |
| Region | `cn-north-4`（默认） |
| Terraform | `>= 1.5.0` |
| huaweicloud Provider | `~> 1.95` |
| 可用区 | region 内至少 2 个可用区 |

## 2. 凭据准备

在华为云「我的凭证」页面获取 Access Key ID 与 Secret Access Key，并由 Terraform Provider 在运行时读取：

```bash
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"
```

> 不要将凭据写入任何代码或配置文件

## 3. 部署步骤

### 3.1 初始化工作目录

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform init
```

预期输出：`Terraform has been successfully initialized!`

### 3.2 自定义配置

按需修改 `variables.tf` 中的默认值：

- `region`：华为云区域
- `identifier`：项目标识（用作资源命名前缀）
- `availability_zones`：可用区列表
- `vpcs`：Spoke VPC 定义（CIDR / 工作负载子网 / 中转子网 / ECS 规格 / 镜像名 / Flow Log 配置）
- `shared_services_vpc`：共享服务 VPC 配置
- `on_premises_cidr`：本地数据中心 CIDR（用于入站 DNS SG 放行）
- `forwarding_rules`：出站 DNS 转发规则

### 3.3 预演资源变更

```bash
terraform plan
```

预期输出：`Plan: N to add, 0 to change, 0 to destroy.`

### 3.4 替换占位 endpoint_id

`huaweicloud_dns_resolver_rule.outbound[*].endpoint_id` 当前为占位值（指向 secgroup），apply 前需替换为 shared services VPC 中自建 DNS 实例的真实 endpoint_id。

如果自建 DNS 尚未部署，建议：

1. 先 apply 当前 IaC（resolver_rule 的 endpoint_id 会因无效而失败，可暂时禁用）
2. 部署自建 DNS 实例（BIND / CoreDNS），记录其 endpoint_id
3. 修改 `infra/main.tf` 中 `huaweicloud_dns_resolver_rule.endpoint_id` 为真实值
4. 再次 apply

或者：

- 在 `infra/main.tf` 中注释掉 `huaweicloud_dns_resolver_rule` 块，先 apply 主体资源
- 部署自建 DNS 后再追加 resolver_rule

### 3.5 执行部署

```bash
terraform apply -auto-approve
```

预期输出：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

部署耗时：约 5-15 分钟（视资源数量）

### 3.6 记录关键输出

```bash
terraform output
```

输出包含：

- VPC ID 集合
- 企业路由器 ID + 路由表 ID
- ECS 实例 ID 集合
- VPCEP ID 集合
- 内网域名 ID 集合
- KMS Key ID
- LTS 日志组 ID
- ECS 实例委托名称

## 4. 自建 DNS 部署（混合 DNS 入站端点）

如需启用「本地数据中心 ↔ 华为云 DNS」双向解析，需在 shared services VPC 的 endpoints 子网内部署自建 DNS：

### 4.1 推荐方案：CoreDNS on ECS

1. 在 shared services VPC 启动 1 台 ECS（CentOS 7.9），加入 endpoints 子网
2. 安装 CoreDNS（`yum install bind-utils` 或 Docker）
3. 配置 CoreDNS 监听 53 端口（tcp + udp），转发至华为云内网 DNS（100.125.0.2 / 100.125.1.2）或直接响应
4. 在华为云「我的凭证」页面获取 Access Key，配置 IAM 委托允许 CoreDNS 查询华为云 DNS API

### 4.2 入站 DNS SG 已放行

`huaweicloud_networking_secgroup.dns_inbound` 已配置：

- 入站 53/tcp + 53/udp（仅放行 `var.on_premises_cidr`）
- 出站：全部放行（用于 CoreDNS 向外部 DNS 服务器转发）

### 4.3 本地数据中心 DNS 配置

在本地 DNS 服务器添加转发规则：

- 域名：`obs.cn-north-4.myhuaweicloud.com` 等
- 目标：自建 DNS 实例的 IP（shared services VPC endpoints 子网内）

## 5. 清理资源

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform destroy -auto-approve
```

预期输出：`Destroy complete! Resources: N destroyed.`

清理注意：

- `terraform destroy` 释放 Terraform state 中追踪的资源
- 若中途通过控制台手动创建资源（如自建 DNS 实例），需手动释放
- KMS Key 删除有 7 天等待期（`pending_days = "7"`）

## 6. 故障排查

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| `terraform init` 失败 | 网络无法访问 `releases.hashicorp.com` | 改用 `terraform init -plugin-dir=<本地 mirror 路径>` 或 `TF_CLI_CONFIG_FILE` 指向 filesystem_mirror 配置 |
| `terraform plan` 报 service_id 错误 | 区域无对应 VPCEP 服务 | 检查 `data.huaweicloud_vpcep_services` 输出，确认 service_name 在 region 可用 |
| `terraform apply` 报 DNS resolver rule endpoint_id 无效 | 占位 secgroup ID 不是真实 DNS 端点 | 见 §3.4 |
| ECS 创建失败 | 镜像 ID 不存在或规格不可用 | 用 `data.huaweicloud_compute_flavors` 查询可用规格，`data.huaweicloud_images_image` 确认镜像名 |
| ECS 无法访问 OBS | VPCEP 未生效 / DNS 解析失败 | 检查 spoke ECS 能否 ping VPCEP 内网 IP；检查 `/etc/resolv.conf` 是否指向华为云内网 DNS |
