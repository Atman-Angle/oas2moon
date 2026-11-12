# oas2moon 生产级验收与测试方案

本文档把申报书、项目规范和生成 SDK 的真实消费者行为统一到一套可重复的放行标准中。

## 1. 验收原则

1. **以公开行为为准。** 通过 CLI、生成包和真实 HTTP 行为验收；内部 IR、实现注释和测试名称不能单独作为证据。
2. **每项支持声明都有正例、反例和边界例。**
3. **unsupported 必须拒绝。** 记录诊断但继续生成错误 SDK，不算通过。
4. **编译和语义分开验收。** `moon check` 只能证明代码合法，不能证明 JSON、HTTP 或类型语义正确。
5. **独立消费者优先。** 验收测试不得依赖生成器内部函数、内部 IR 或实现细节。
6. **证据可复现。** 每个结论记录提交 SHA、工具链版本、命令、fixture、输出摘要和退出码。
7. **申报书、支持矩阵和实现必须一致。** 任意冲突都阻断发布，必须修实现或缩小公开承诺。

## 2. 发布前置条件

冻结候选版本并记录：

```pwsh
git status --short
git rev-parse HEAD
moon version
python --version
```

候选版本必须没有未记录的源代码改动；明确生成器和 MoonBit 版本；fixture 不依赖网络、时间、随机数或本机绝对路径；验收输出写入独立构建目录。

## 3. 申报承诺验收矩阵

每一行都要绑定测试 ID、fixture 和独立消费者断言。

| 能力 | 必测输入 | 必测错误/边界 | 通过条件 |
|---|---|---|---|
| OpenAPI 3.0.0–3.0.3 | 四个版本号 JSON | 2.0、3.1 | 3.0.x 正确处理，其他版本稳定拒绝 |
| JSON/YAML | 等价 JSON/YAML | 锚点、空值、未知结构 | 等价输入结果一致，不支持语法明确失败 |
| 本地 `$ref` | 组件 object、enum、array、嵌套 ref | 缺失、外部、循环 ref | 本地 ref 正确，外部 ref 明确拒绝 |
| primitive | string、boolean、int32、int64、float、double | 错误 JSON 类型、null | MoonBit 类型、编码、解码均正确 |
| object → struct | 组件/内联/嵌套/数组内/request/response object | 空 object、额外字段、命名冲突 | 消费者能访问字段，编码解码保持语义 |
| array[T] | 内联数组、组件数组、数组 ref、数组内 object、嵌套数组 | 空数组、null item、错误 item | 生成 `Array[T]`，合法列表完整解码 |
| enum | string enum、保留字、冲突值 | 未知/重复/非 string enum | 可表示时生成 enum，否则明确诊断或安全回退 |
| required/optional/nullable | 四种组合 | 缺失、null、具体值、错误类型 | 请求区分 Unset/Null/Value，响应行为明确 |
| additionalProperties | bool、schema、无声明 | 非 object、字段冲突 | 动态字段不丢失，语义与文档一致 |
| JSON 编解码 | 所有模型作请求和响应 | 错误字段、类型、截断 JSON | 成功值正确，失败带结构化路径 |
| Int/Int64 | 普通值、边界值、精度边界 | `9007199254740993`、越界、小数、指数、布尔 | 精确保留或明确拒绝，不得静默舍入 |
| 操作方法 | GET/POST/PUT/PATCH/DELETE | 缺参数、无 body、错误方法 | 签名、请求、响应类型正确 |
| path/query/header | scalar、array、保留字符、Unicode | matrix、label、deepObject、cookie | 支持样式正确，其他样式稳定拒绝 |
| request body | application/json、optional body | 缺 body、null、错误 media type | Content-Type、body 和缺失语义正确 |
| responses | 200、201、204、同 schema、多 schema | 未声明状态、错误 Content-Type | direct、Unit、response enum 和错误正确 |
| authentication | Bearer、Basic、API key header/query | 缺凭证、错误组合、alternatives | 正确加凭证，缺凭证在网络前失败 |
| servers/base URL | server、覆盖、无 server | 未解析变量、非法 URL | URL 可用且不会拼错 |
| unsupported | oneOf、anyOf、allOf、discriminator、multipart、XML | 嵌套、request/response 中出现 | CLI 非零退出，诊断稳定，不产出误导 SDK |
| determinism | 多次生成、key 顺序变化 | 时间、随机目录、并发 | 源文件和诊断字节一致 |

**特别门禁：** 若支持矩阵把内联 object 定义为 `Json` fallback，而申报书仍承诺所有 `object→struct`，必须先修实现或修改承诺，不能同时标为支持。

## 4. 独立消费者架构

建立隔离目录：

```text
acceptance/
  specs/
  consumer/
  servers/
  expected/
  run_review.ps1
  acceptance-matrix.md
```

每个正例执行：

```text
OpenAPI -> CLI generate -> moon fmt --check -> moon check -> moon test
       -> local HTTP server -> generated client request -> decode -> assertions
```

消费者不得读取 IR 代替调用 SDK、调用未公开辅助函数、只检查生成文本、只用 CaptureTransport 证明 wire 行为，或把“不崩溃”当成解码成功。

## 5. 核心反例

### object/array

必须有：内联 object 属性、组件 object、组件顶层 array、`Array[Object]`、嵌套数组、request body 内联 object、response 内联 object、嵌套 object 和数组。每个都测试完整 JSON、空数组、额外字段、缺失字段和错误类型。

### Int64 精度与范围

使用十进制原始 JSON 测试：

```text
0
1
9007199254740991
9007199254740992
9007199254740993
9223372036854775807
-9223372036854775808
9223372036854775808
-9223372036854775809
1.0
1e3
true
"9007199254740993"
```

成功值必须等于输入整数；失败值必须产生明确 decode error。不能先转 Double 再用范围判断作为精确性证明。

### unsupported 与联合类型

对 `oneOf`、`anyOf`、`allOf`、`discriminator` 覆盖组件、内联属性、request body、response、数组 item 五个位置。每个 case 断言：

```text
exit code != 0
diagnostic.code == 预期 code
diagnostic.json_pointer == 预期 pointer
没有生成可编译的 SDK
```

若决定安全回退到 `Json`，必须提供 wire-preservation 证明并在支持矩阵中单独标注。

## 6. HTTP 行为验收

本地严格 fixture server 记录方法、路径、query、headers、body 和调用次数。验证 path 编码、query/header scalar 和 array、JSON body、Content-Type、四类认证、200/201/204、多成功 schema、非 2xx 错误、错误 media type，以及缺凭证是否在网络前失败。每个 wire case 同时有服务端观测和客户端断言。

## 7. 生成包质量门禁

每个代表性 fixture 运行：

```pwsh
moon fmt --check
moon check
moon test
```

同时检查 imports、模型、操作和响应排序稳定；无时间戳、随机 ID、本机绝对路径；生成包可被另一个 MoonBit 包导入；动态 `Json` fallback 有明确文档；错误包含 operation id、状态、headers/body 或 decode path。

## 8. 确定性与并发

同一输入至少三次生成：不同目录、JSON key 顺序变化、两个并行进程、Windows PowerShell 和 CI。比较整个生成目录的相对文件列表和 SHA-256。未文档化的任何差异都阻断发布。

## 9. 回归测试

每个已发现 bug 留下最小 fixture，包含原始 OpenAPI、最小请求/响应、错误版本失败记录、修复版本通过记录和 sibling cases。回归测试必须验证用户可见行为，不能只断言 IR 改变。

## 10. 独立审查协议

审查者只接收申报书、支持矩阵、CLI 文档和生成结果，不预先阅读实现者结论。必须重新建立矩阵，自己设计正例、边界例和负例，检查测试在错误实现上是否会失败，检查 unsupported 是否阻止生成，检查三份文档是否一致，并为每项问题提供输入、命令、输出和严重级别。

报告分为：已复现缺陷、源码风险、未验证承诺、建议缩小的支持范围。没有证据的“看起来没问题”不算通过。

## 11. 放行标准

以下任意一项不满足，候选版本不得提交：

- 核心承诺没有独立消费者证据；
- 任一正例生成包不能 fmt/check/test；
- 合法输入在请求或响应中被静默改变；
- 越界、错误类型或 unsupported 被静默接受；
- unsupported 只记录诊断但仍生成误导 SDK；
- 真实 HTTP 没有服务端观测；
- 生成结果不确定；
- 存在未解释的高严重级别问题；
- 申报书与支持矩阵不一致；
- 验收日志缺少 SHA、工具链版本或复现命令。

放行报告至少包含：

```text
candidate_sha
toolchain_versions
test_command
case_count
pass_count
fail_count
unsupported_rejections
real_http_cases
determinism_hashes
known_limits
reviewer_report
release_decision
```

## 12. 执行顺序

1. 先跑 unsupported 负例，确认不会静默吞掉；
2. 再跑 object/array/Int64 核心反例；
3. 再跑独立消费者完整 HTTP 链路；
4. 再跑模型、操作、认证和响应策略正例；
5. 再跑跨平台、并发和确定性；
6. 最后由独立审查者决定放行。

验收报告只记录实际运行结果。“应该通过”“理论上支持”“代码已经覆盖”都不能替代命令输出和消费者证据。
 
