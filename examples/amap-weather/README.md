# 高德天气真实 API 示例

这个示例使用高德 Web 服务天气查询 API，验证 `oas2moon` 生成的 SDK 能够：

- 使用 query API key 认证；
- 编码必填和可选 query 参数；
- 发起真实 HTTPS GET 请求；
- 将 JSON 响应解码为生成的 MoonBit 类型。

## 准备

在高德开放平台创建 Web 服务 Key，然后仅在当前 PowerShell 会话设置环境变量：

```powershell
$env:AMAP_KEY = "在本机粘贴你的 Key"
```

不要把 Key 写入 OpenAPI 文件、提交记录或聊天消息。

## 生成、检查并调用 API

在仓库根目录设置 Key 后运行脚本。脚本会生成 SDK、运行 `moon fmt` 与
`moon check`，然后调用高德 HTTPS API 并打印返回的天气记录：

```powershell
pwsh -NoProfile -File examples/amap-weather/run.ps1
```

`local/` 已加入 `.gitignore`，生成产物和本机凭据不会上传到 GitHub。

## 接口来源

- [高德天气查询文档](https://lbs.amap.com/api/webservice/guide/api/weatherinfo)
- Endpoint: `https://restapi.amap.com/v3/weather/weatherInfo`
- 必填参数：`city`、`key`
- 本 fixture 默认使用 `extensions=base` 和 `output=JSON`

真实测试记录应填写在 `local/EXTERNAL_API_TEST.md`，不要复制到仓库。
