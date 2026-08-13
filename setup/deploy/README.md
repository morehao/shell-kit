# Deploy

服务部署脚本集合。（环境初始化脚本见 `../bootstrap`。）

## 脚本列表

| 脚本 | 说明 | 依赖 |
|------|------|------|
| `deploy_mihomo.sh` | 通过订阅地址部署 Mihomo 代理服务（Docker） | Docker / Docker Compose |

## 使用方法

```bash
cd setup/deploy
chmod +x deploy_mihomo.sh
./deploy_mihomo.sh -u "https://your-subscription-url"
```

更多参数说明见脚本内帮助：`./deploy_mihomo.sh --help`
