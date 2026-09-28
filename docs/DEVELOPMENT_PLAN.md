# oas2moon 决赛冲刺开发计划

> 版本：2026-09-14；依据报名材料、项目规范、架构、支持矩阵与验收标准制定。
>
> 目标不是“堆功能”，而是交付一个评委可复现、开发者可使用、证据可核验的完整闭环：
> **OpenAPI → 诊断/规范化 → 类型化 MoonBit SDK → 编译通过 → 真实 HTTP 正确 → 可重复生成**。

## 一、当前真实位置

### 已有证据

- 已通过报名初审（截图仅证明报名资格，不等于最终技术验收通过）。
- Phase 1、1.5、2、2.5 已完成；模型生成、JSON 编解码、命名、诊断、确定性生成已有基础。
- 当前项目状态应保持为 `SPIKE_VERIFIED`，不能提前宣称 `V1_VERIFIED`。
- 生产主路径为 MoonBit；Python 仅作为测试辅助/参考 oracle。

### 最大风险

1. 还没有可供用户直接调用的操作方法、CLI 和运行时闭环；
2. 生成代码的 HTTP 语义（编码、状态码、错误、鉴权）尚缺真实服务证据；
3. README 与申报材料中有“计划支持”的内容，最终必须改成实测数据；
4. GitHub/OpenAI 等大规格不能直接作为“全量支持”承诺，必须先做可量化 subset/corpus；
5. Windows、许可证、依赖来源、发布包和答辩演示仍是获奖级交付的关键差异化证据。

## 二、获奖策略

评委最容易记住的不是支持了多少 OpenAPI 关键字，而是四件事：

- **完整闭环**：输入一个真实 spec，几分钟内得到可编译、可调用的 MoonBit SDK；
- **正确性证据**：真实本地 HTTP server 验证请求线与响应解码，不只测字符串；
- **工程可信度**：不支持的语义明确报错，生成可重复，CI 可复现；
- **MoonBit 生态价值**：不是一次性 demo，而是可复用 runtime、清晰 IR、CLI、示例和文档。

明确不做：OpenAPI 3.1、外部/网络 `$ref`、oneOf/anyOf、multipart、XML、OAuth flow、任意参数样式。把边界写清楚本身是质量分。

## 三、分阶段计划与出口条件

### Sprint 0：冻结合同与演示场景（9/14—9/15）

**产出**

- 冻结 V1 支持矩阵、诊断编号和 CLI 参数；
- 选定一个 3 分钟答辩主场景：Petstore CRUD + Bearer + 204 + 错误响应；
- 建立 `docs/DECISIONS.md`，记录 URL 编码、数组 query、nullable、响应策略等不可逆决策；
- 为每个阶段建立“代码、测试、文档、证据”四项检查表。

**出口**：任何新增功能都能映射到支持矩阵和验收条目；不允许临时扩大范围。

### Sprint 1：最小完整纵切片（9/16—9/22）

**目标**：先打通一个可用 operation，而不是先实现所有边角。

- Client/Request/Response IR；
- GET + path/query/header；
- JSON response typed decode；
- base URL override；
- runtime transport adapter，生成操作代码不直接散落 async/http 调用；
- 生成包 `moon fmt`、`moon check`。

**出口**：Petstore `get_pet_by_id` 生成后可编译，并向真实本地服务发送正确 method/path/query/header，收到 typed `Pet`。

### Sprint 2：写操作与响应语义（9/23—9/29）

- POST/PUT/PATCH/DELETE；
- JSON request body；
- 200/201/204；
- 多个成功状态：同 schema 直返，不同 schema 生成 operation response enum；
- 非 2xx 结构化 SDK error；
- 缺失 body、空 body、错误 JSON 的明确行为。

**出口**：真实 server 集成测试覆盖 CRUD、JSON body、204、typed decode、非 2xx。

### Sprint 3：鉴权与参数正确性（9/30—10/6）

- Bearer、Basic、API key header/query；
- 必填凭据缺失时 clean failure；
- path percent-encoding；
- query scalar/array 的 V1 form 规则；
- header scalar/array；
- unsupported style/media type 产生稳定 diagnostic。

**出口**：请求断言覆盖所有 auth 方式和编码规则；诊断排序及 JSON pointer 稳定。

### Sprint 4：CLI 与开发者体验（10/7—10/13）

- `oas2moon generate <input> --module <name> --out <dir>`；
- JSON/YAML 输入、配置错误、覆盖输出策略；
- stdout/stderr、退出码、诊断格式；
- `--check`/dry-run（若实现成本可控）；
- README 从“计划”改为“已验证/不支持”；
- 一个从零开始可复制的示例和录屏脚本。

**出口**：陌生用户按 README 从 spec 生成并运行示例，不依赖仓库内部路径。

### Sprint 5：真实语料、确定性与跨平台（10/14—10/20）

- Petstore 全量 fixture；
- GitHub、OpenAI、第三个传统 REST API 的**精选 subset**；
- 每个 corpus 输出：总 operations、支持数、拒绝数、拒绝原因、compile pass；
- 同输入两次比较文件列表、字节、diagnostics；
- Ubuntu + Windows CI；
- 清理临时产物、绝对路径、未跟踪申请材料中的敏感信息。

**出口**：所有声称支持的 corpus case 生成并编译；失败均可解释；CI 绿。

### Sprint 6：发布与答辩打磨（10/21—10/27）

- 发布候选版本、CHANGELOG、许可证/第三方依赖说明；
- Mooncakes 包可行性评估（若阻塞则不强行发布）；
- 生成 SDK 示例项目；
- 5 分钟演示：spec → generate → check → server → typed result → error → regenerate hash；
- 评委问答：为何不是 OpenAPI Generator 移植、边界为何克制、MoonBit 原生价值、失败如何保证不静默；
- 冻结功能，进入只修 bug 和文档阶段。

**出口**：候选包可由第三方在干净环境复现；README、CI、演示、验收数字一致。

## 四、工作拆分优先级

### P0：必须先完成

1. Runtime + Client/Operation IR；
2. GET 纵切片；
3. POST/DELETE/204/错误；
4. CLI；
5. 真实 HTTP 集成测试；
6. Windows CI/本地验证。

### P1：决定完成度与奖项竞争力

1. 四类鉴权；
2. 稳定诊断与 unsupported negative fixtures；
3. 三个真实 API subset；
4. 确定性回归与指标报告；
5. README、示例、录屏。

### P2：只有 P0/P1 稳定后再考虑

- HEAD；
- `application/*+json`；
- 更丰富的 CLI 输出格式；
- Mooncakes 发布优化。

## 五、每项功能的完成定义

任何功能只有同时满足以下条件才标记完成：

1. Canonical IR 有明确表示；
2. 至少一个正向 fixture；
3. 至少一个边界或负向 fixture；
4. 生成文件通过 `moon fmt` 和 `moon check`；
5. 涉及 wire semantics 时有真实 HTTP 断言；
6. deterministic regen 通过；
7. README、支持矩阵、验收表同步；
8. 有一个可引用的 CI/命令输出证据。

## 六、最终发布指标模板

不要提前填数字，发布前由脚本生成：

```text
Specs                         <measured>
Operations                    <measured>
Generated packages            <passed>/<total>
moon fmt                      <passed>/<total>
moon check                    <passed>/<total>
HTTP integration              <passed>/<total>
Deterministic regeneration   <passed>/<total>
Unsupported semantics        <all diagnosed>
Platforms                    Ubuntu + Windows
```

## 七、每日节奏与防失控规则

- 每天只推进一个 P0/P1 可验收切片；先写失败测试，再实现；
- 每个合并提交只解决一个主题，提交信息说明 capability + evidence；
- 连续两天卡在生态 API 时，先做最小 spike，不要盲猜依赖；
- 任何“为了支持更多 spec”而引入的复杂度，必须先证明不会破坏 deterministic、compile 和 no-silent-fallback；
- 截止前 7 天停止扩展范围，只做修复、回归、文档和演示。

## 八、下一步立即执行（今天）

1. 在 `docs/DECISIONS.md` 冻结 runtime/request/response 合同；
2. 建立 `fixtures/operations/`：GET path/query/header、POST body、204、multi-status、error、四种 auth；
3. 实现并验证第一条 `GET /pets/{id}` 完整纵切片；
4. 把生成包 compile test 接入现有测试入口；
5. 更新 README 的状态栏：明确“模型已验证，操作/runtime/CLI 尚未完成”，直到证据改变；
6. 建立 `docs/EVIDENCE_MATRIX.md`，逐条绑定 `ACCEPTANCE.md` 条目、测试命令和输出文件。

## 九、建议的最终项目定位

> **一个以正确性和可复现性为核心、面向 MoonBit 生态的 OpenAPI 3.0.x 类型化客户端 SDK 生成器。**
>
> 不承诺“支持所有 OpenAPI”，而承诺：在明确的 common profile 内，生成可编译、可调用、可验证、可重复的 MoonBit SDK。
