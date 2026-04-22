# Changelog

## [1.2.0] - 2026-04-22

### Features

- **iOS App**: 新增原生 iOS App，支持远程监控 Claude Code 会话
  - Session 列表展示（状态、路径、模型、运行时长）
  - 状态颜色指示（running=绿 / waiting=橙 / idle=灰）
  - 远程 confirm / reject 工具调用权限
  - Settings 页面配置 Tailscale IP 和端口
  - 通过 scheme pre-action 自动启动本地 server 进行测试
- **App Icon**: 设计并应用全新 App Icon（CC 字母 + 终端符号）
- **测试**: 添加单元测试和 UI 测试
  - `DashboardAPITests`: API 请求与错误处理测试
  - `SessionModelTests`: 数据模型解码测试
  - `SettingsStoreTests`: 设置存储与 baseURL 拼接测试
  - `AppIconTests`: 图标非占位符验证测试
  - `SessionListUITests`: 启动、设置按钮、Sheet 打开关闭等 UI 测试
- **文档**: 添加软件工程规范文档
  - 功能规格说明（FSD）
  - 详细设计文档
  - 用户手册
  - 测试案例

### Fixes

- 修复 Swift 6 严格并发编译错误
- 修复 UI 测试稳定性（ToolbarItem 点击、Sheet 关闭验证）
- 优化 URL 验证逻辑（scheme 白名单 + host 非空检查）

## [1.1.1] - 2026-04-03

### Features

- 支持 transcript 中的 image 类型 content block 并允许 data: URL 预览

### Fixes

- 修复聊天弹窗中图片无法点击放大的问题

## [1.1.0] - 2026-04-02

### Features

- **实时聊天监控**: 支持在 Dashboard 中查看和发送 Claude 对话消息
  - SSE 客户端实时推送新消息
  - 浮动卡片中集成聊天面板
  - 聊天消息支持 Markdown 格式化和图片预览
  - 主页 Session 卡片添加可折叠迷你实时对话面板
- **API 扩展**: `POST /action` 支持 `sendMessage` 动作
- **SSE 端点**: `/api/sessions/:id/stream` 实时消息流

### Fixes

- 修复聊天图片无法预览的问题
- 修复代码审查发现的健壮性与安全问题
- 修复聊天弹窗标题栏与关闭按钮重叠问题

## [1.0.0] - 2026-04-01

### Features

- **Dashboard 核心功能**: Claude Code CLI 实时监控 Web 界面
  - Session 列表卡片展示
  - 状态颜色指示（running / waiting / idle）
  - 远程 confirm / reject 工具调用权限
  - Node.js 服务器提供 API（`/api/sessions`, `POST /action`）
  - 深色科技主题 UI（霓虹蓝/紫渐变，毛玻璃效果）
