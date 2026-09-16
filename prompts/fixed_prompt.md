## OAS2Moon DeepSeek 固定提示词

### 每次必须发送

你正在开发 D:\oas2moon 项目。

请先阅读并遵守：
1. AGENTS.md
2. docs/PROJECT_SPEC.md
3. docs/ARCHITECTURE.md
4. docs/SUPPORTED_OPENAPI.md
5. docs/ACCEPTANCE.md
6. docs/DEVELOPMENT_SPEC.md
7. docs/DEVELOPMENT_TASKS.md

项目目标：
将 OpenAPI 3.0.x JSON/YAML 转换为可编译、类型安全、可实际调用 HTTP API 的 MoonBit Client SDK。

### 分支管理规则

1. 以当前 main 为基线，每个 TASK 开一个 feat/tXX-xxx 分支；
2. 只修改当前任务对应的文件，不混入其他任务改动；
3. 修改前先 git status 确认当前分支正确；
4. 改完后提交到当前 feat 分支，不直接推送到 main；
5. 合并前必须通过该任务的所有测试，main 不允许直接推送。

### 开发约束

- 先检查仓库现状，不要假设已有实现。
- 不要绕过 Canonical Client IR。
- 不要把 Parser AST 直接交给 Codegen。
- 不支持的语义必须报稳定诊断，禁止 silent fallback。
- 生成代码必须通过 moon fmt 和 moon check。
- 涉及 HTTP 的功能必须用真实本地 HTTP server 验证。
- 保持确定性生成：无时间戳、随机 ID、绝对路径和不稳定排序。
- 不扩大 V1 范围：不实现 OpenAPI 3.1、external ref、oneOf/anyOf、multipart、XML、OAuth flow。
- Windows 环境优先使用 PowerShell 命令和 rg。
- 不要修改与当前任务无关的模块。
- 不要只报告方案，直接完成当前任务的代码、测试和文档。
- 如果遇到不确定的 MoonBit API，先做最小验证，不要凭记忆猜测。

### 完成后必须报告

1. 修改了哪些文件；
2. 实现了什么；
3. 执行了哪些验证命令；
4. 验证结果；
5. 尚未解决的问题；
6. 下一步建议。

如果测试失败，继续定位并修复，不要停在"已发现问题"。
