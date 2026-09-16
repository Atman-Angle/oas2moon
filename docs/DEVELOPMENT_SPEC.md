# OAS2Moon 后续开发规格说明

> 版本：v0.1-draft
> 日期：2026-09-15
> 项目目标：将 OAS2Moon 从“模型代码生成原型”推进为“OpenAPI 3.0.x → MoonBit Typed SDK Compiler”。

## 1. 文档目的

本文件定义 OAS2Moon 后续开发的产品边界、架构契约、功能规格、测试要求、验收门槛和发布条件。它是后续实现、测试、README 和答辩材料的共同依据。

本文件不扩大当前 V1 支持范围。所有新增能力必须先更新支持矩阵、IR、测试和验收证据，禁止通过隐式降级掩盖不支持的 OpenAPI 语义。

## 2. 终态定义

用户输入一份 OpenAPI 3.0.x JSON/YAML 文档后，工具应生成一套独立的 MoonBit Client SDK，满足：

1. 生成结果通过 `moon fmt`；
2. 生成结果通过 `moon check`；
3. 生成结果可被 MoonBit 项目调用；
4. 支持范围内的请求能正确发送到真实 HTTP 服务；
5. 支持范围内的响应能解码为有用的 MoonBit 类型；
6. 非 2xx 响应转换为结构化错误；
7. 不支持的语义产生稳定诊断；
8. 相同输入和配置产生字节一致的输出。

最终用户体验：

```bash
oas2moon generate openapi.yaml --module petstore --out ./generated
```

```moonbit
let client = @petstore.Client::new(
  base_url="http://127.0.0.1:8080",
  bearer_token=token,
)

// 必填参数按位置传递，可选参数用具名形式（`name? : T`）。
// 操作方法是 `async`，失败通过 `raise SdkError` 表达。
let pet = client.get_pet_by_id(123L, "trace-id")
println(pet.name)
```

## 3. 范围与非目标

### 3.1 V1 范围

- OpenAPI 3.0.0–3.0.3；
- JSON 和常见 YAML；
- 本地 `$ref`；
- string、integer、number、boolean、array、object、enum；
- required、optional、nullable；
- `additionalProperties`；
- GET、POST、PUT、PATCH、DELETE；
- path、query、header 参数；
- `application/json`；
- 200、201、204 和多个成功状态；
- Bearer、Basic、API key header、API key query；
- 显式 `base_url` 覆盖；
- 确定性生成和编译验证。

### 3.2 明确不做

V1 不实现或不声称支持：

- OpenAPI 3.1；
- external/network `$ref`；
- `oneOf`、`anyOf`、discriminator；
- multipart；
- XML；
- callbacks/webhooks；
- OAuth authorization flows；
- cookie、matrix、label、deepObject 等非 common profile 参数样式；
- 任意 request body 编码；
- 未经验证的流式二进制传输。

## 4. 总体架构

```text
OpenAPI JSON/YAML
        ↓
Frontend Adapter
        ↓
Frontend Model
        ↓
Support Validator
        ↓
Canonical Client IR
        ↓
Normalizer / Naming / Type Mapping
        ↓
MoonBit Client IR
        ↓
Codegen Backend
        ↓
Generated SDK + Runtime Dependency
```

模块边界：

- **Frontend Adapter**：只负责解析生态模型并提取必要原始信息；
- **Frontend Model**：表达输入文档，不作为 codegen 权威；
- **Support Validator**：识别支持、Json fallback 和拒绝项；
- **Canonical Client IR**：唯一的 API 语义权威；
- **Normalizer**：合并、解析、排序、命名和类型映射；
- **MoonBit Client IR**：面向源码输出的中间表示；
- **Codegen Backend**：只消费 MoonBit Client IR；
- **Runtime**：封装 transport、请求、响应、鉴权和错误，不散落在操作代码中；
- **CLI**：负责输入、配置、诊断、输出和退出码。

## 5. Canonical Client IR 规格

IR 至少需要表达以下对象：

```text
Document
Server
Model
Field
Enum
TypeRef
Operation
Parameter
RequestBody
Response
SecurityScheme
SecurityRequirement
Diagnostic
```

### 5.1 Operation

```text
Operation {
  operation_id: StableName
  method: HttpMethod
  path: String
  tags: Array[String]
  parameters: Array[Parameter]
  request_body: Optional[RequestBody]
  success_responses: Array[Response]
  error_responses: Array[Response]
  security: SecurityPolicy
  source_location: SourceLocation
}
```

### 5.2 Parameter

```text
Parameter {
  name: String
  location: Path | Query | Header
  required: Bool
  nullable: Bool
  explode: Bool
  style: SupportedStyle | UnsupportedStyle
  type: TypeRef
  source_location: SourceLocation
}
```

### 5.3 Response

```text
Response {
  status: StatusCode | Default
  description: String
  media_type: Optional[String]
  body_type: Optional[TypeRef]
  headers: Array[HeaderSpec]
}
```

### 5.4 IR 不变量

- 所有 `$ref` 在进入 codegen 前完成解析或产生诊断；
- 所有 operation 拥有稳定名称；
- 所有数组、模型、字段和操作按稳定键排序；
- 不在 IR 中保存机器绝对路径、时间戳和随机 ID；
- optional 与 nullable 必须保持可区分；
- unsupported semantics 不得被转换成看似正常的 wire behavior；
- 每个诊断保留 JSON Pointer 和 operation id（如适用）。

## 6. 代码生成规格

### 6.1 生成包

每个生成包固定为下面这套**平铺**布局（与 `DECISIONS.md` §8 一致，不设
`model/`、`operation/`、`runtime/` 子目录）：

```text
moon.mod            # 模块名；有 operation 时声明 moonbitlang/async 依赖
moon.pkg            # imports；由 codegen 独占，下游不得改写
models.mbt          # struct、enum、Presence、JSON codec
client.mbt          # 公开 Client 与全部 operation 方法（无 operation 时不生成）
runtime.mbt         # SdkError、Request/Response、Transport、CaptureTransport
config.mbt          # base_url 与凭据
encoding.mbt        # path/query/header 序列化
http_transport.mbt  # 唯一接触 moonbitlang/async/http 的文件
```

错误模型在 `runtime.mbt`，鉴权配置在 `config.mbt` 与 `runtime.mbt`；不存在
`errors.mbt`、`auth.mbt`、`operations/*.mbt`。runtime 以内联源码方式随包生成，
使生成包自包含、无版本漂移；代价是 runtime 修复必须重新生成 SDK。

### 6.2 模型

支持以下映射：

```text
string          → String
integer/int32   → Int
integer/int64   → Int64
number/float    → Float
number/double   → Double
boolean         → Bool
array[T]        → Array[T]
object          → struct
enum            → enum
free-form       → Json
```

必须生成：

- MoonBit 类型；
- JSON encode/decode；
- required 校验；
- optional 字段；
- nullable 字段；
- optional + nullable 的三态语义；
- 嵌套 schema；
- local ref；
- reserved identifier 和命名冲突处理。

### 6.3 操作方法

生成的操作 API 必须：

- 使用类型化参数；
- 自动拼装 base URL 和 path；
- 正确编码 path/query；
- 自动注入 header 和 Content-Type；
- 自动序列化 JSON body；
- 自动按状态码选择响应策略；
- 返回 `Result[T, SdkError]` 或等价的明确错误模型。

### 6.4 响应策略

```text
单一有效成功 schema              → Result[T, SdkError]
只有 204                         → Result[Unit, SdkError]
多个成功状态且 schema 相同         → Result[T, SdkError]
多个成功状态且 schema 不同         → Result[OperationResponse, SdkError]
非 2xx                           → SdkError::Http
无法安全静态映射但 wire 正确        → Json + warning
```

## 7. Runtime 规格

Runtime 是生成操作与 HTTP 实现之间的唯一边界。

至少提供：

```text
Request
Response
Transport
Headers
QueryParams
Auth
SdkError
request_json
decode_json
```

`SdkError` 至少区分：

```text
TransportError
HttpError(status, headers, body)
DecodeError
MissingCredential
InvalidRequest
UnsupportedFeature
```

生成操作代码不得在各处直接调用 `moonbitlang/async/http`。底层 transport 应可替换，以便同时支持：

- 真实 HTTP transport；
- capture/mock transport；
- 测试 fixture transport。

## 8. 参数、鉴权和服务器

### 8.1 参数序列化

V1 仅支持：

- path scalar：common simple；
- query scalar：common form；
- query array：明确的 form 规则；
- header scalar：common simple；
- header array：common simple。

不支持的 style/explode 组合必须报稳定诊断。

必须覆盖 percent-encoding、空值、optional、数组和参数名冲突。

### 8.2 鉴权

支持：

- HTTP Bearer；
- HTTP Basic；
- API key header；
- API key query；
- anonymous operation。

凭据由 Client 配置持有。缺失必填凭据必须 clean failure，不得发送错误请求。

### 8.3 Server

- 优先使用可解析的 `servers[0]`；
- 支持显式 `base_url` 覆盖；
- 缺失 servers 时仍可通过 base_url 使用；
- 复杂 server variables 未实现时不得拼出畸形 URL。

## 9. 诊断规格

诊断统一包含：

```text
code
severity
json_pointer
operation_id
message
suggestion
```

要求：

- code 稳定；
- JSON Pointer 可定位；
- 多个诊断稳定排序；
- CLI 使用非零退出码表示生成失败；
- diagnostics 不包含绝对本机路径；
- unsupported feature 不得静默忽略。

示例：

```text
OAS203 ERROR
Unsupported schema feature: oneOf
location: #/components/schemas/Payment
suggestion: use a supported object schema or explicitly use Json where wire semantics remain correct
```

## 10. CLI 规格

命令：

```bash
oas2moon generate <input> --module <module> --out <directory>
```

最低要求：

- JSON/YAML 输入；
- 输入文件不存在时返回明确错误；
- module 和 out 校验；
- 输出目录策略明确；
- 稳定退出码；
- 诊断输出到 stderr；
- 成功输出文件列表或摘要；
- 不依赖仓库内部 fixture 路径；
- 支持 Windows 和 Ubuntu。

可选能力（P0 完成后）：

- `--check`；
- dry-run；
- diagnostics JSON；
- 版本信息；
- 生成摘要统计。

## 11. 测试规格

每项支持能力必须至少有：

1. parse/normalize 测试；
2. codegen 测试；
3. 生成包 compile 测试；
4. wire semantics 相关的真实 HTTP 测试；
5. 一个边界或 negative fixture。

### 11.1 最小 fixture 集合

- GET path/query/header；
- POST JSON body；
- PUT/PATCH；
- DELETE + 204；
- multiple success statuses；
- non-2xx error；
- Bearer；
- Basic；
- API key header；
- API key query；
- percent encoding；
- optional/nullable body；
- unsupported oneOf；
- unsupported parameter style；
- unsupported media type；
- naming collision/reserved words。

### 11.2 真实 HTTP 验证

本地 HTTP server 必须断言：

- method；
- URL path；
- query；
- headers；
- Content-Type；
- body；
- auth；
- response status；
- typed decode；
- non-2xx error。

### 11.3 Determinism

至少比较：

- 生成文件列表；
- 文件字节；
- imports 顺序；
- 类型/操作顺序；
- diagnostics 顺序；
- 无时间戳、随机 ID、绝对路径。

## 12. 开发阶段

### Gate A：第一条纵切片

GET path/query/header + JSON response + runtime + generated package compile + real HTTP。

### Gate B：V1 操作闭环

POST/PUT/PATCH/DELETE、JSON body、201、204、多状态响应、结构化错误。

### Gate C：生产可用性

四种鉴权、CLI、稳定 diagnostics、README quick start、Windows/Ubuntu 验证。

### Gate D：发布可信度

三个真实 API subset、指标报告、确定性回归、许可证和依赖说明、可复现演示。

任何 Gate 未通过，不得把项目状态标记为 `V1_VERIFIED`。

## 13. 发布验收

发布前必须提供实测指标，不得填写估算值：

```text
Specs                         <measured>
Operations                    <measured>
Generated packages            <passed>/<total>
moon fmt                      <passed>/<total>
moon check                    <passed>/<total>
moon test                     <passed>/<total>
HTTP integration              <passed>/<total>
Deterministic regeneration    <passed>/<total>
Unsupported semantics        all diagnosed
Platforms                    Ubuntu + Windows
```

README 的每一项“Supported”必须能追溯到测试、命令和 CI 证据。

## 14. 完成定义

OAS2Moon 只有在以下条件全部满足时，才能宣称 V1 完成：

- 生成器能从 OpenAPI 3.0.x 得到 Canonical Client IR；
- 支持范围内的模型和操作均能生成；
- 生成包通过 `moon fmt`、`moon check`、`moon test`；
- 至少一个真实 API 场景完成真实 HTTP 调用；
- 认证、错误、204 和多状态响应均有测试；
- 不支持语义都有稳定诊断；
- 确定性生成通过；
- Ubuntu 和 Windows 验证通过；
- README、支持矩阵、许可证和使用说明完整；
- 项目提交记录能反映连续、真实的功能演进。

## 15. 当前最高优先级

按以下顺序实现：

1. Client/Operation IR；
2. Runtime request/response/transport 契约；
3. GET `/pets/{id}` 完整纵切片；
4. POST/DELETE/204/结构化错误；
5. Bearer、Basic、API key；
6. CLI `generate`；
7. 真实 API subset 和指标报告；
8. Windows CI、发布包和答辩 Demo。

禁止在上述闭环完成前扩展 OpenAPI 3.1、union、multipart 或任意参数样式。
