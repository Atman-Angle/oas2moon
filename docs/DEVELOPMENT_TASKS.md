# OAS2Moon 开发任务分片

> 基线规格：`docs/DEVELOPMENT_SPEC.md`
> 制定日期：2026-09-16
> 目标：将规格拆成可独立开发、测试、审查和验收的任务。

## 0. 分片原则

- 每个任务只拥有一个主要责任边界；
- 每个任务必须同时产出代码、测试和证据；
- 任务按纵向闭环推进，不先堆积孤立基础设施；
- 下游任务不得绕过 Canonical Client IR；
- 未通过出口条件，不进入下一阶段；
- 未经确认不得扩大 V1 范围。

任务状态统一使用：`TODO`、`IN_PROGRESS`、`BLOCKED`、`DONE`。

## 1. 依赖关系总览

```text
T00 合同冻结
  ├── T01 Operation IR
  │     ├── T02 Request/Response Runtime
  │     │     └── T03 GET 纵切片
  │     ├── T04 Parameter Serialization
  │     └── T05 Response Strategy
  ├── T06 Operation Codegen
  │     └── T07 CRUD + JSON Body
  ├── T08 Error Model
  ├── T09 Authentication
  └── T10 CLI

T03 + T07 + T08 + T09 + T10
  └── T11 End-to-End Petstore Demo

T11
  ├── T12 Corpus & Metrics
  ├── T13 Determinism Hardening
  ├── T14 Cross-platform CI
  └── T15 Release Documentation
```

## 2. 任务分片

### T00：开发合同冻结

**目标**：冻结不会频繁变化的公共契约。

**范围**：runtime、错误、响应、命名、输出目录、CLI 退出码、参数编码。

**产出**：

- `docs/DECISIONS.md`；
- `docs/EVIDENCE_MATRIX.md` 初版；
- 对 `DEVELOPMENT_SPEC.md` 中未决项作出决定。

**验收**：每个 P0 任务都有明确输入、输出和测试依据；不再直接依赖猜测的 MoonBit API。

**依赖**：无。

**建议提交**：`docs: freeze sdk and runtime contracts`

---

### T01：Operation / Client Canonical IR

**目标**：让 paths、operations、parameters、request body、responses、security 进入项目自有 IR。

**范围**：

- HTTP method/path；
- operationId 和缺失 operationId 命名；
- tags；
- path/query/header 参数；
- request body；
- success/error responses；
- security requirement；
- source location。

**不包含**：代码生成、底层 HTTP 调用。

**测试**：

- Petstore GET/POST/DELETE parse/normalize；
- path-level 与 operation-level parameter 合并；
- 稳定排序；
- 缺失 operationId；
- 重名操作。

**出口**：Canonical IR 序列化快照稳定，重复运行结果一致，unsupported 输入有诊断。

**依赖**：T00。

---

### T02：Runtime Request / Response / Transport

**目标**：建立生成操作与 HTTP 实现之间唯一的 runtime 边界。

**范围**：

- Request；
- Response；
- Headers；
- body；
- Transport 接口；
- JSON request/decode 辅助；
- `SdkError` 基础类型。

**不包含**：各 API 操作代码、鉴权具体策略。

**测试**：capture transport、transport error、response body、headers、status。

**出口**：可通过替换 transport 测试请求；生成代码无需直接散落 async/http 调用。

**依赖**：T00。

---

### T03：GET 最小完整纵切片

**目标**：完成第一个真实可调用的 GET SDK 方法。

**范围**：GET + path 参数 + query + header + JSON response + base URL。

**测试**：

- 生成 Petstore `get_pet_by_id`；
- `moon fmt`；
- `moon check`；
- 真实本地 HTTP server 断言 method/path/query/header；
- typed `Pet` decode。

**出口**：从 OpenAPI 输入到 `Result[Pet, SdkError]` 的链路全通。

**依赖**：T01、T02。

**这是第一道强制 Gate。**

---

### T04：参数序列化

**目标**：集中实现正确的 path/query/header 编码。

**范围**：

- path scalar/simple；
- query scalar/form；
- query array；
- header scalar/simple；
- header array/simple；
- percent encoding；
- optional/empty value。

**不包含**：cookie、matrix、label、deepObject。

**测试**：特殊字符、空数组、重复 query key、参数名冲突、未支持 style。

**出口**：所有 wire semantics 有真实 HTTP 断言；不支持 style 产生稳定诊断。

**依赖**：T00、T01、T02。

---

### T05：响应策略

**目标**：把状态码和 schema 转成稳定的返回类型。

**范围**：

- 200/201；
- 204 → Unit；
- 同 schema 多成功状态；
- 不同 schema 多成功状态 → response enum；
- 空 body；
- content type 检查。

**测试**：响应矩阵 fixture、状态码选择、错误 body、decode failure。

**出口**：每个 operation 的 response strategy 可在 IR 中观察，并有 codegen 测试。

**依赖**：T01、T02。

---

### T06：Operation MoonBit Codegen

**目标**：从 Operation IR 生成 MoonBit client 方法。

**范围**：

- Client 定义；
- method 签名；
- request 构造；
- runtime 调用；
- response decode；
- 稳定 imports 和文件排序。

**不包含**：CLI、真实 transport 实现。

**测试**：方法签名快照、生成包 fmt/check、命名冲突、reserved words。

**出口**：至少一个 operation 可以从 IR 生成可编译 MoonBit 源码。

**依赖**：T01、T02、T03、T04、T05。

---

### T07：CRUD 与 JSON Request Body

**目标**：完成 V1 的主要 HTTP 操作闭环。

**范围**：POST、PUT、PATCH、DELETE、JSON body、Content-Type、201、204。

**测试**：真实 server 检查 method、body、header、响应和错误。

**出口**：Petstore CRUD 演示通过；无 body 和 204 不触发错误 decode。

**依赖**：T03、T04、T05、T06。

**这是第二道强制 Gate。**

---

### T08：结构化错误

**目标**：统一 transport、HTTP、decode、credential、invalid request、unsupported feature 错误。

**范围**：

- status；
- response headers；
- raw body；
- operation id；
- stable display；
- 错误响应 schema（如 V1 可安全支持）。

**测试**：400/401/404/500、网络失败、错误 JSON、空错误 body。

**出口**：非 2xx 永远不会伪装成成功结果，错误可被调用方分支处理。

**依赖**：T02、T05、T06。

---

### T09：鉴权

**目标**：实现 V1 四类鉴权并验证真实请求。

**范围**：Bearer、Basic、API key header、API key query、anonymous。

**测试**：每类成功请求、缺凭据失败、security requirement 选择、请求断言。

**出口**：认证逻辑集中在 runtime/client config；操作代码不重复实现鉴权。

**依赖**：T01、T02、T06、T08。

---

### T10：CLI `generate`

**目标**：让仓库外的用户能独立生成 SDK。

**范围**：输入、module、out、JSON/YAML、诊断、退出码、输出摘要。

**测试**：成功、文件不存在、非法 module、unsupported spec、重复生成、Windows path。

**出口**：README 中的单条命令可在干净目录运行，不依赖 tests/ 或 fixtures/ 内部路径。

**依赖**：T06、T08。

---

### T11：Petstore 端到端 Demo

**目标**：构建答辩和回归的标准演示。

**范围**：generate、fmt、check、test、真实 server、typed result、204、错误、重复生成 hash。

**产出**：

- `demo/petstore/`；
- `demo/run_demo.ps1`；
- 演示日志；
- 端到端测试报告。

**出口**：第三方按 README 可在干净环境复现完整流程。

**依赖**：T03、T07、T08、T09、T10。

**这是项目是否从原型进入产品的核心 Gate。**

---

### T12：真实 API Corpus 与指标

**目标**：证明通用性，但不夸大支持范围。

**范围**：Petstore、GitHub subset、OpenAI subset、一个传统 REST API subset。

**产出**：自动统计：

```text
operations_total
operations_supported
operations_rejected
rejection_reasons
compile_pass
```

**出口**：所有声称支持的 case 均生成并编译；失败原因可追溯。

**依赖**：T10、T11、T13。

---

### T13：确定性与回归硬化

**目标**：保证相同输入得到字节一致输出。

**测试**：文件列表、文件字节、imports、IR 顺序、诊断顺序、无时间戳/随机 ID/绝对路径。

**出口**：连续生成比较全部通过，纳入 CI。

**依赖**：T06、T10。

---

### T14：Ubuntu / Windows CI

**目标**：建立项目可复现的跨平台证据。

**范围**：generator tests、generated package fmt/check/test（工具链可用时）、HTTP integration、determinism。

**出口**：README 的平台声明与 CI 实际结果一致。

**依赖**：T11、T12、T13。

---

### T15：发布文档与生态交付

**目标**：把工程成果变成可被评审和使用的产品。

**范围**：README、支持矩阵、LICENSE、第三方依赖、CHANGELOG、版本标签、quick start、架构图、FAQ、已知限制、答辩脚本。

**出口**：README 每个 Supported 都能追溯到测试/CI；仓库无敏感信息和临时产物；发布流程可复现。

**依赖**：T12、T14。

## 3. 推荐执行顺序

### 第一阶段：打通产品核心

```text
T00 → T01 → T02 → T03 → T04/T05 → T06
```

### 第二阶段：完成 API Client

```text
T07 → T08 → T09
```

### 第三阶段：交付用户入口

```text
T10 → T11
```

### 第四阶段：建立获奖证据

```text
T13 → T12 → T14 → T15
```

## 4. Definition of Ready

任务开始前必须具备：

- 明确上游契约；
- 明确不包含的范围；
- 至少一个输入 fixture；
- 已知 MoonBit API 或完成最小 spike；
- 明确验证命令；
- 不会破坏现有模型生成路径。

## 5. Definition of Done

任务完成必须满足：

- 代码实现完成；
- 正向测试通过；
- 边界或负向测试通过；
- 生成代码通过适用的 `moon fmt` / `moon check`；
- wire semantics 已使用真实 HTTP 验证（如适用）；
- deterministic 检查通过；
- 文档和支持矩阵已同步；
- Git 提交信息清晰；
- 没有把未验证能力写成 Supported。

## 6. 当前迭代看板

| ID | 任务 | 状态 | 立即下一步 |
|---|---|---|---|
| T00 | 开发合同冻结 | TODO | 建立 `docs/DECISIONS.md` |
| T01 | Operation / Client IR | TODO | 盘点现有 IR 与 frontend 输出 |
| T02 | Runtime 契约 | TODO | 做 transport 最小 API spike |
| T03 | GET 纵切片 | TODO | 添加 GET fixture 和失败测试 |
| T04 | 参数序列化 | TODO | 固定 query/path 编码规则 |
| T05 | 响应策略 | TODO | 建立状态码矩阵 fixture |
| T06 | Operation Codegen | DONE | 设计生成文件与方法模板 |
| T07 | CRUD/body | TODO | 先实现 POST + 204 |
| T08 | 错误 | TODO | 定义 `SdkError` |
| T09 | 鉴权 | TODO | 先做 Bearer |
| T10 | CLI | TODO | 确定入口包和参数解析方式 |
| T11 | E2E Demo | TODO | 准备 demo 目录结构 |
| T12 | Corpus | TODO | 建立统计脚本接口 |
| T13 | Determinism | TODO | 将双生成比较纳入测试 |
| T14 | CI | TODO | 复制现有 Ubuntu workflow 后补 Windows |
| T15 | Release | TODO | 维护 README 与支持矩阵 |

## 7. 风险与升级规则

- MoonBit HTTP/async API 不确定时，先创建 spike，不直接大规模编码；
- 如果 runtime API 与生成代码耦合，暂停扩展操作种类并回到 T00/T02；
- 如果真实 corpus 支持率过低，先分析拒绝原因，再决定是否调整 V1 支持矩阵；
- 如果 Windows 工具链不可用，必须准确记录限制，不能声称 Windows compile verified；
- 若发现成熟直接竞品，暂停扩展实现并重新评估项目定位；
- 任何 silent fallback 都视为阻断问题，而不是普通 bug。

