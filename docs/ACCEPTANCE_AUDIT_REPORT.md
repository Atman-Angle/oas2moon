# Acceptance Audit Report

## Scope

本轮审计覆盖 frontend adapter、Canonical Client IR、support validator、MoonBit codegen、runtime、CLI 输出目录复用、输入版本边界、认证、真实 HTTP demo、corpus 以及 CI 验收门禁。审计依据为 `docs/PROJECT_SPEC.md`、`docs/ARCHITECTURE.md`、`docs/SUPPORTED_OPENAPI.md` 和 `docs/ACCEPTANCE.md`。

审计结论只针对仓库声明的 bounded OpenAPI 3.0.0–3.0.3 profile。没有把未声明的 OpenAPI 能力当作已实现功能。

## Findings And Fixes

以下问题已在当前工作树修复，并由回归测试或生成包检查覆盖。

| 问题 | 修复 |
|---|---|
| 非法数字开头的 operationId、schema property 名称 | 命名器生成稳定的 `n_`/`N` 前缀，并通过真实生成包 `moon check`。 |
| query array alias 且 `explode=false` 使用未声明 `joined_query` | codegen 按解析后的 alias 类型决定是否声明并传入 joined query。 |
| 复用 output directory 残留旧 client/runtime 文件 | CLI 只清理 generator-owned 文件，model-only 输出不再残留 operation code。 |
| 无 operation 包复制无用 HTTP transport 或缺失 runtime imports | CLI 按 operation 数量复制 runtime，并补齐 `utf8`、`string` imports。 |
| 组件 parameter、requestBody、response `$ref` 的 wire 字段丢失 | adapter 使用窄 raw sidecar 恢复本地 component 的名称、位置、required、content 和 schema。 |
| nullable component ref 在 response/body/field 中丢失 | lowering 建立 nullable component identity，并生成 `Nullable` type。 |
| mixed-case Bearer/Basic scheme 被错误归类 | validator/lowering 统一按小写 scheme token 处理。 |
| Authorization apiKey 与 Bearer/Basic 的 AND 组合覆盖 header | support validator 输出稳定 `unsupported.auth`，拒绝不可表达组合。 |
| 3.0.4、3.1.x 被错误接受或诊断不稳定 | adapter 在 mooncontract parse 前统一拒绝非 3.0.0–3.0.3，输出 `unsupported.version`。 |
| `.YAML`/`.YML` 扩展名不识别 | 输入扩展名按大小写不敏感方式判断。 |
| raw schema 缺省字段为 `null` 破坏 Frontend Model 合约 | adapter 固定输出 `nullable=false`、`required=[]`、`enum=[]`。 |
| `application/*+json` 可绕过 validator 后在 codegen 失败 | 当前生成 profile 只接受精确 `application/json`，其他 media type 稳定输出 `unsupported.media_type`。runtime 仍能解析 JSON structured suffix 作为运行时输入。 |

## Verification

| 命令或场景 | 结果 |
|---|---|
| `python -m pytest tests -q` | `125 passed` on the current working tree, including nullable primitive component references in responses and required fields. |
| frontend `moon fmt --check`、`moon check --target native --deny-warn` | pass |
| core `moon fmt --check`、`moon check --target native --deny-warn`、`moon test --target native --deny-warn` | pass，`8/8` tests |
| codegen `moon fmt --check`、`moon check --target native --deny-warn` | pass |
| runtime `moon fmt --check`、`moon check --target native --deny-warn`、`moon test --target native --deny-warn` | pass，`33/33` tests |
| `tests/test_input_boundaries.py` | `5 passed`, including the nullable primitive component-reference generated-package test. |
| `tests/test_generation_edge_cases.py`、`tests/test_auth_regressions.py` | `7 passed` |
| `pwsh -NoProfile -File demo/petstore/run_demo.ps1 -Port 18186` | `ALL PASS (11 checks)`，19 E2E assertions，12 wire requests，9 generated files byte-identical |
| `python tools/corpus_metrics.py ...` | all `7/7` generated packages compile，real-world `5/5` specs and `12/12` operations compile |
| `git diff --check` | pass |

## Supported Boundary

当前实现仍明确不支持 OpenAPI 3.1、外部/网络/cyclic `$ref`、`oneOf`/`anyOf`/`allOf`/discriminator、multipart/XML/binary、callbacks/webhooks、OAuth/OpenID Connect、cookie parameters、任意参数 serialization style、非 `application/json` 的声明式请求/响应 media type，以及未实现 HTTP 方法。support validator 应对这些输入给出稳定诊断，不能静默生成错误 wire 行为。

schema-valued `additionalProperties` 保留为 `Map[String, Json]`，这是文档化的安全 JSON fallback，不是 typed map 承诺。内联 object 同样保留 JSON wire 语义并产生 `schema.json_fallback` warning。YAML 仅承诺常见格式，未承诺所有 YAML 边界语法。

Int64 的当前 profile 证据覆盖 JSON number、2^53 外整数和 Int64 边界值，并拒绝字符串、非整数分数、布尔值和越界值。整数值的 decimal/exponent 词法会基于原始 JSON number lexeme 精确解析，避免 Double 舍入把 `0.99999999999999999` 误收为 `1`。

## Remaining Evidence Limits

- 本地工作树验证不等同于候选提交在 hosted Ubuntu/Windows CI 上通过。CI 工作流已配置对应门禁，但本轮未取得新的 hosted run 结果。
- corpus 是有边界的本地样本，不代表所有真实 OpenAPI 文档的通过率。
- 运行时可解析 `+json` Content-Type，但生成器对声明式 media type 只接受 `application/json`，两者是不同层次的行为。

## Release Decision

在独立修复后审计 agent 完成只读复核并确认没有新的 material finding 后，才能把当前工作树视为满足文档化 V1 profile。未声明的能力不纳入放行结论。
