# oas2moon — 项目申报书

> 基于 OpenAPI 接口描述规范的 MoonBit 类型化 HTTP 客户端 SDK 生成器

---

## 项目名称

**oas2moon**

## 项目简介

oas2moon 是一个**确定性的、编译可验证**的代码生成工具。它读取 OpenAPI 3.0.x 接口描述规范文档，自动生成**类型安全的 MoonBit HTTP 客户端 SDK**。

Web API 的开发者不再需要手写模型类型、JSON 编解码、HTTP 调用和鉴权代码——只要提供一份 OpenAPI 规范，oas2moon 就能产出开箱即用的 MoonBit 客户端。

## 项目方向与通用性

本项目不是为某一个特定 API 服务的。oas2moon 接受**任意符合 OpenAPI 3.0.x 标准**的 API 规范文档作为输入，生成对应的 MoonBit SDK。

适用场景包括但不限于：云服务 API 的 MoonBit 客户端、微服务间调用的类型化 SDK、创业公司或开源项目的 MoonBit API 封装。

当前实现支持 OpenAPI 规范中的对象、枚举、数组、可选/必填/可为空字段等常见结构，能够将 API 数据模型完整映射为 MoonBit 类型。

## 使用场景

**场景一：云 API 调用**
一个 MoonBit 后端服务需要调用第三方 REST API（例如 GitHub REST API、OpenAI API 等）。开发者只需将对应的 OpenAPI 规范文件交给 oas2moon，即可获得一个类型完备的 MoonBit 客户端，直接通过命名参数调用 API 方法，无需手动拼接 URL 或处理 JSON 序列化。

**场景二：微服务间类型安全通信**
团队内部使用 MoonBit 开发，各微服务公开 OpenAPI 规范。oas2moon 自动为每个服务生成对应的客户端 SDK，确保请求/响应类型在编译期即可校验，避免运行时因类型不匹配导致的错误。

**场景三：API 封装库的自动化维护**
开源项目的 API 封装库通常需要跟随上游 API 变更手动更新。oas2moon 可以将 OpenAPI 规范作为单一事实来源，每次规范更新后重新生成 SDK，自动保持模型类型、请求参数与响应结构同步，降低维护成本。

## 拟实现核心功能

| 功能 | 状态 |
|---|---|
| OpenAPI 3.0.x 规范解析（JSON / YAML） | ✅ 已完成 |
| 原始类型 → MoonBit 类型映射（String、Bool、Int、Int64、Double） | ✅ 已完成 |
| MoonBit 结构体、枚举自动生成及 JSON 编解码 | ✅ 已完成 |
| 必填/可选/可为空字段及其三态（未设置/空/有值） | ✅ 已完成 |
| 支持状态判定（自动识别并分类为支持/回退/不支持） | ✅ 已完成 |
| 确定性生成（相同输入 → 字节一致输出） | ✅ 已完成 |
| HTTP 操作生成（GET/POST/PUT/PATCH/DELETE、参数序列化、认证注入） | 🔄 进行中 |
| 命令行工具（oas2moon generate） | 🔄 进行中 |

## 原创性与参考说明

本项目的核心创新点在于**填补 MoonBit 生态中类型化 API 客户端生成能力空白**。OpenAPI 代码生成的概念在 Java（OpenAPI Generator）、Go（oapi-codegen）等语言生态中已较为成熟，但 MoonBit 作为较新的现代系统编程语言，尚缺少类似工具。

oas2moon 在架构上采用了独特的**分阶段管线**设计：MoonBit 前端适配器 → 项目自有的版本化前端模型 → 支持状态验证 → 规范化的客户端 IR → MoonBit 代码生成。各阶段边界清晰，未直接拷贝或移植任何现有工具的实现。

项目使用了以下开源依赖：
- **Han-Wentao/mooncontract**（OpenAPI 3.0 解析库，仅在前端适配器中使用）
- **moonbitlang/async**（异步 HTTP 传输层）
- **moonbitlang/x**（MoonBit 标准库扩展）
- **moonbit-community/yaml**（YAML 格式支持）

## GitHub 仓库

**https://github.com/Atman-Angle/oas2moon**

## 有效 Commit 情况

主分支（`main`）已有 **14 次有效提交**，包含核心功能实现、修复、CI 配置与文档更新。无合并提交或 WIP 提交。
