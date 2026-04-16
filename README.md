# Claude Code CLI Dashboard

一个具有科技感的实时监控面板，用于可视化展示本地 Claude Code CLI 的使用情况。

## 功能特性

- **Session 监控**: 自动读取 `~/.claude/sessions`，展示所有活跃会话
- **实时状态**: 显示每个 session 的当前状态（执行中 / 等待确认 / 空闲）
- **执行时长**: 实时更新的运行时间计时器
- **Context 占用**: 可视化进度条展示当前上下文窗口使用情况，细分为消息估算、系统/工具估算、空闲空间
- **Token 统计**: 显示累计 Input / Output / 总计 Token 消耗
- **工作目录**: 显示每个 session 的工作路径，按目录名稳定排序
- **模型信息**: 显示使用的 Claude 模型版本
- **最近交互**: 展示最近 10 条交互消息，等待确认的消息会高亮显示
- **远程确认**: 当 session 处于"等待确认"状态时，可在 Dashboard 中直接发送确认/拒绝指令（支持 Terminal.app / iTerm2）
- **独立实时对话弹窗**: 点击主页卡片右上角的气泡图标打开居中对话窗，通过 SSE 实时接收 session 中的消息流
- **Markdown 渲染**: 聊天消息支持 Markdown 格式化（代码块、链接、列表、表格、引用等）
- **图片预览**: 自动识别并渲染聊天中的图片，支持点击放大预览
- **远程发送消息**: 在 Dashboard 中直接向 Terminal.app / iTerm2 中的 session 发送文本消息，Claude 即时回复

## 设计风格

- 深色科技主题
- 霓虹蓝/紫色渐变配色
- 毛玻璃效果卡片
- 动态粒子背景
- 状态指示灯动画
- 增量 DOM 更新，无闪屏

## 快速开始

```bash
# 启动 Node.js 服务器
node server.js

# 访问 Dashboard
open http://localhost:7777
```

## API 接口

### GET `/api/sessions`

返回所有活跃 session 的实时数据，包含：

- `id`, `pid`, `status`
- `workDir`, `model`
- `contextUsed`, `contextBreakdown`
- `tokensInput`, `tokensOutput`
- `recentMessages`
- `pendingTools`

### GET `/api/sessions/:id/stream`

SSE 端点，实时推送指定 session 的 transcript 新增消息：

```bash
curl -N http://localhost:7777/api/sessions/:id/stream
```

连接建立后会先推送最近 50 条历史消息，随后每秒检查文件变化并推送新消息。当 session 进程结束或 transcript 被截断时，会分别发送 `event: close` 和 `event: reset`。

每 15 秒发送一次心跳保持连接。

### POST `/api/sessions/:id/action`

对指定 session 发送操作指令：

```bash
# 确认/拒绝
curl -X POST http://localhost:7777/api/sessions/:id/action \
  -H "Content-Type: application/json" \
  -d '{"action":"confirm"}'

# 发送消息
curl -X POST http://localhost:7777/api/sessions/:id/action \
  -H "Content-Type: application/json" \
  -d '{"action":"sendMessage","text":"帮我优化代码"}'
```

`action` 可选值：`confirm` | `reject` | `sendMessage`

> 远程操作通过 AppleScript 向 Terminal.app 或 iTerm2 发送按键实现。VS Code 集成终端、Warp 等第三方终端暂不支持。

## 数据集成

Dashboard 自动从以下位置读取真实数据：

1. `~/.claude/sessions/*.json` — 获取 session 基础信息（PID、工作目录、模型等）
2. `~/.claude/projects/*/<session-id>.jsonl` — 解析 transcript 获取：
   - 最后一条 assistant 消息的 `usage`（context 占用、token 统计）
   - 最近 10 条 user/assistant 交互消息
   - `stop_reason === 'tool_use'` 时提取待确认的工具调用信息
   - 聊天图片路径识别与转换

无需额外配置，只要本地有活跃的 Claude Code CLI 会话，Dashboard 即可自动展示。

## 技术栈

- HTML5 + Tailwind CSS（CDN）
- 原生 JavaScript（单文件应用，无构建步骤）
- marked.js（Markdown 渲染）
- Node.js（数据收集与静态文件服务）

## 文件结构

```
cc-dashboard/
├── index.html      # 主页面（前端所有代码）
├── server.js       # Node.js 服务器（API + 静态文件 + 图片代理）
├── README.md       # 说明文档
└── docs/           # 设计文档与计划
```

## 浏览器兼容性

- Chrome / Edge / Safari / Firefox 最新版
- 推荐使用 WebKit 内核浏览器以获得最佳的 `backdrop-filter` 效果

## 更新日志

### v1.1.1 (2026-04-17)

- 修复聊天弹窗中 base64 图片无法显示的问题（支持 transcript 中的 `image` 类型 content block）
- 修复聊天弹窗中图片无法点击放大的问题（事件捕获阶段监听，避免被 `stopPropagation` 拦截）
- 对超大 base64 图片增加 1MB 降级保护，避免前端渲染卡顿

### v1.1.0 (2026-04-16)

- 新增独立实时对话弹窗，通过主页卡片右上角气泡图标打开
- 聊天消息支持 Markdown 格式化与代码块样式
- 聊天图片支持点击放大预览
- SSE 连接增加进程存活检查、文件截断重连、错误重试机制
- 增加静态文件路径遍历防护与图片缓存安全路由
- 优化 AppleScript 字符串转义与消息长度限制

### v1.0.0

- 初始版本发布，支持 Session 监控、Context 可视化、远程确认操作

## License

MIT
