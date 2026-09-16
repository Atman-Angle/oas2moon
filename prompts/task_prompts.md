# OAS2Moon 任务提示词模板

> 配合 `prompts/fixed_prompt.md` 使用。
> 打开新窗口时，发送 fixed_prompt.md + 对应任务的提示词。
> 每个窗口只负责一个任务，完成后检查是否满足 DoD 再合并。

---

## T00：开发合同冻结

执行 T00：开发合同冻结。

目标：
建立并完善：
- docs/DECISIONS.md
- docs/EVIDENCE_MATRIX.md

请根据 DEVELOPMENT_SPEC.md 和 DEVELOPMENT_TASKS.md，冻结以下契约：
- Runtime Request/Response
- SdkError
- 响应状态码策略
- optional/nullable
- path/query/header 编码
- 鉴权配置
- CLI 退出码
- 生成目录结构
- diagnostics 格式
- 确定性排序规则

要求：
- 先检查现有代码和文档，避免重复或冲突；
- 只做文档和必要的契约补充，不实现大功能；
- 对无法确认的 MoonBit API 标记为待 spike；
- 最后检查文档之间是否存在矛盾。

---

## T01：Operation / Client IR

执行 T01：Operation / Client Canonical IR。

目标：
把 OpenAPI paths 转换为项目自己的 Operation/Client Canonical IR。

支持：
- method/path
- operationId
- 缺失 operationId 的稳定命名
- tags
- path/query/header 参数
- request body
- success/error responses
- security requirements
- source location

要求：
- 先阅读现有 frontend 和 core IR；
- 不要让 codegen 直接依赖 OpenAPI AST；
- 复用已有命名、类型映射和诊断机制；
- 保持稳定排序；
- 增加正向、边界和负向测试；
- 不实现 HTTP runtime 和 codegen。

出口：
Petstore 的 GET/POST/DELETE 能生成稳定的 Operation IR，
重复运行输出一致，unsupported 输入产生诊断。

---

## T02：Runtime

执行 T02：Runtime Request/Response/Transport。

目标：
建立生成操作与 HTTP 实现之间唯一的 Runtime 边界。

实现：
- Request
- Response
- Headers
- body
- Transport 接口
- JSON request/decode 辅助
- 基础 SdkError

要求：
- 先检查现有 MoonBit async/http 依赖和实际 API；
- 不凭记忆假设库接口；
- 支持 capture/mock transport；
- 生成操作不得直接散落底层 HTTP 调用；
- 增加 transport error、status、headers、body 测试；
- 不实现具体 API operation。

出口：
可以通过替换 transport 测试请求和响应，
并通过 MoonBit 工具链验证 runtime。

---

## T03：GET 纵切片

执行 T03：GET 最小完整纵切片。

目标：
打通 Petstore 的 GET /pets/{id}。

实现：
- Operation IR 到 MoonBit GET 方法；
- path 参数；
- query 参数；
- header 参数；
- base_url；
- JSON response decode；
- Result[Pet, SdkError] 或项目确定的等价类型。

要求：
- 使用真实本地 HTTP server；
- 断言 method、path、query、header；
- 验证 typed Pet decode；
- 生成包通过 moon fmt 和 moon check；
- 增加失败测试；
- 不扩大到 POST、鉴权或复杂响应。

这是 Gate A，必须形成完整证据。

---

## T04：参数序列化

执行 T04：参数序列化。

实现 V1 支持的：
- path scalar/simple；
- query scalar/form；
- query array；
- header scalar/simple；
- header array/simple；
- percent encoding；
- optional/empty value。

要求：
- 先检查现有 URL/字符串工具；
- 不实现 cookie、matrix、label、deepObject；
- 真实 HTTP server 断言最终请求；
- unsupported style/explode 必须输出稳定诊断；
- 增加特殊字符、空数组、重复 query key 测试；
- 保持参数顺序稳定。

---

## T05：响应策略

执行 T05：响应策略。

目标：
将 OpenAPI responses 归一化为稳定的响应策略和 MoonBit 返回类型。

实现：
- 200/201；
- 204 → Unit；
- 多成功状态且 schema 相同；
- 多成功状态且 schema 不同 → response enum；
- 空 body；
- content type 检查；
- decode failure。

要求：
- 先扩展 Canonical IR，不要直接在字符串模板中判断；
- 增加状态码矩阵 fixture；
- 增加 codegen 测试；
- 明确非 2xx 交给 SdkError；
- 不支持的 media type 不得静默处理。

---

## T06：Operation Codegen

执行 T06：Operation MoonBit Codegen。

目标：
从 Canonical Client IR 生成可编译的 MoonBit Client 方法。

实现：
- Client；
- operation method；
- typed 参数；
- Request 构造；
- Runtime 调用；
- response decode；
- 稳定 imports；
- 稳定文件和方法排序。

要求：
- Codegen 只能消费 Canonical/MoonBit Client IR；
- 不直接读取 OpenAPI AST；
- 复用已有模型生成和命名逻辑；
- 增加方法签名快照；
- 生成包通过 moon fmt 和 moon check；
- 不实现 CLI。

---

## T07：CRUD 和 JSON Body

执行 T07：CRUD 与 JSON Request Body。

实现：
- POST；
- PUT；
- PATCH；
- DELETE；
- application/json request body；
- Content-Type；
- 201；
- 204。

要求：
- 使用真实本地 HTTP server；
- 断言 method、body、headers、status；
- 验证 request model JSON 编码；
- 204 不进行错误的 JSON decode；
- 添加缺 body、空 body 和错误 body 测试；
- 保持现有 GET 测试通过。

---

## T08：结构化错误

执行 T08：结构化 SdkError。

目标：
统一 transport、HTTP、decode、credential、invalid request 和 unsupported feature 错误。

实现并测试：
- status；
- headers；
- raw body；
- operation id；
- stable display；
- 400/401/404/500；
- 网络失败；
- 错误 JSON；
- 空错误 body。

要求：
- 非 2xx 不得返回成功结果；
- 错误信息不得包含本机绝对路径；
- 保持错误字段可供调用方程序化判断；
- 更新 DEVELOPMENT_SPEC.md 和证据矩阵。

---

## T09：鉴权

执行 T09：鉴权。

按顺序实现：
1. Bearer；
2. Basic；
3. API key header；
4. API key query；
5. anonymous operation。

要求：
- 鉴权配置集中在 Client/runtime；
- 不在每个 operation 中复制鉴权逻辑；
- 使用真实 HTTP server 检查 header/query；
- 缺失必填凭据必须 clean failure；
- 增加每种鉴权的正向和负向 fixture；
- 不实现 OAuth flow。

---

## T10：CLI

执行 T10：CLI generate。

目标：
实现：

oas2moon generate <input> --module <module> --out <directory>

要求：
- 支持 JSON/YAML；
- 校验 input/module/out；
- 稳定退出码；
- diagnostics 输出到 stderr；
- 成功输出生成摘要；
- 不依赖仓库内部 fixture 路径；
- 支持 Windows PowerShell 调用；
- 增加成功、输入不存在、非法 module、unsupported spec、重复生成测试；
- README 增加最小使用示例。

不要在本任务中实现新 OpenAPI 特性。

---

## T11：Petstore E2E Demo

执行 T11：Petstore 端到端 Demo。

创建：
- demo/petstore/
- demo/run_demo.ps1
- 端到端测试和说明

流程必须包含：
1. generate；
2. moon fmt；
3. moon check；
4. moon test；
5. 启动本地 HTTP server；
6. typed GET；
7. JSON POST；
8. DELETE + 204；
9. 非 2xx 错误；
10. 重复生成并比较 hash。

要求：
- 第三方只按照 README 即可运行；
- 不依赖开发者本机绝对路径；
- 生成结果、命令和日志可用于答辩展示。

---

## T12：真实 API Corpus

执行 T12：真实 API Corpus 与指标。

加入并统计：
- Petstore；
- GitHub subset；
- OpenAI subset；
- 一个传统 REST API subset。

输出：
- operations_total；
- operations_supported；
- operations_rejected；
- rejection_reasons；
- compile_pass。

要求：
- 不声称完整支持 GitHub/OpenAI；
- 只报告实际可验证结果；
- 每个拒绝项必须有原因；
- 生成包必须通过适用的 fmt/check；
- 增加自动化统计脚本和报告文档。

---

## T13：确定性

执行 T13：确定性与回归硬化。

验证同一输入重复生成时：
- 文件列表一致；
- 文件字节一致；
- imports 顺序一致；
- IR 排序一致；
- diagnostics 顺序一致；
- 无时间戳；
- 无随机 ID；
- 无绝对路径。

要求：
- 把检查接入自动化测试或 CI；
- 修复发现的不稳定 map/filesystem iteration；
- 不通过放宽比较规则来"修复"测试。

---

## T14：跨平台 CI

执行 T14：Ubuntu / Windows CI。

目标：
补充 Windows 和 Ubuntu 的可复现验证。

至少覆盖：
- generator tests；
- fixture tests；
- generated package fmt/check；
- HTTP integration；
- deterministic regeneration。

要求：
- 先检查现有 Ubuntu workflow；
- Windows 使用 PowerShell 兼容命令；
- 如果 MoonBit 工具链在某平台不可用，准确记录限制；
- 不把未执行的 compile verification 写成已通过；
- 更新 README 的平台声明。

---

## T15：发布和答辩材料

执行 T15：发布文档与生态交付。

完善：
- README；
- SUPPORTED_OPENAPI.md；
- ACCEPTANCE.md；
- CHANGELOG；
- LICENSE；
- 第三方依赖说明；
- quick start；
- 架构图；
- 已知限制；
- 答辩 Demo 脚本。

要求：
- README 的 Supported 必须有测试或 CI 证据；
- 删除"计划支持"与实际状态矛盾的表述；
- 不虚构测试指标；
- 检查仓库中是否存在敏感信息、临时产物和绝对路径；
- 准备 5 分钟演示流程。
