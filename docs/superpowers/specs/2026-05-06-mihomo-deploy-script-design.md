# Mihomo 部署脚本设计

## 概述

在 `server-init/deploy_mihomo.sh` 创建独立的 Mihomo 部署脚本，支持通过命令行参数指定订阅地址并自动完成部署。

## 目标

用户只需执行：
```bash
./deploy_mihomo.sh -u "https://your-subscription-url"
```
即可完成 Mihomo 代理的完整部署。

## 功能设计

### 1. 命令行参数

| 参数 | 说明 | 必需 |
|------|------|------|
| `-u, --url` | 订阅地址 | 是 |
| `-h, --help` | 显示帮助信息 | 否 |

### 2. 部署流程

1. **环境检查** - 检测 Docker 和 Docker Compose 是否已安装
2. **目录创建** - 创建 `/opt/mihomo/data` 目录
3. **订阅获取** - 下载订阅内容并提取 `proxies` 和 `proxy-groups` 保存到 `proxies.yaml`
4. **配置生成** - 生成 `docker-compose.yml` 和 `config.yaml`
5. **容器启动** - 执行 `docker compose up -d`
6. **验证提示** - 输出验证命令

### 3. 配置文件

**docker-compose.yml** - 挂载目录、端口、设备权限等标准配置

**config.yaml** - Mihomo 主配置：
- `mixed-port: 7890` - HTTP/SOCKS5 混合代理端口
- `bind-address: 127.0.0.1` - 仅本地监听
- `allow-lan: false` - 禁止局域网访问
- `proxy-providers` - 使用本地文件 Provider
- `proxy-groups` - 代理组配置

### 4. 错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| Docker 未安装 | 提示安装命令并退出 |
| 订阅地址为空 | 显示帮助信息并退出 |
| 订阅下载失败 | 提示检查订阅地址并退出 |
| 目录创建失败 | 提示错误并退出 |
| Docker Compose 启动失败 | 提示查看日志 |

## 文件结构

```
server-init/
└── deploy_mihomo.sh    # 部署脚本（可执行）
```

## 安全性

- 仅本地访问：`bind-address: 127.0.0.1`, `allow-lan: false`
- API 限制访问：`external-controller: 127.0.0.1:9093`
