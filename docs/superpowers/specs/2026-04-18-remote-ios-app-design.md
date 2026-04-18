# Claude Code Dashboard — 远程 iOS App 设计文档

## 1. 项目背景与目标

### 1.1 背景
cc-dashboard 是一个基于 Node.js + 单页 HTML 的 Claude Code CLI 实时监控面板，通过读取 `~/.claude/sessions/` 和 `~/.claude/projects/` 展示本地活跃 session 的状态、context 占用、token 消耗等信息，并支持远程确认/拒绝操作。

### 1.2 目标
在现有 web dashboard 的基础上，开发一个 iOS 原生 App，让用户**出门在外时**能够用手机远程查看和管理电脑上的 Claude session，核心解决"不在家时 Claude 弹出确认请求无法处理"的问题。

## 2. 核心场景

- 用户在公司/外出时，Claude 在电脑上执行需要权限的操作（如修改文件、执行命令）
- 手机收到通知（或用户主动打开 App），查看 session 状态
- 对于"等待确认"的 session，直接在手机上确认或拒绝
- 不需要开电脑，不需要远程桌面

## 3. 技术架构

```
┌─────────────────────────────────────────────────────────────────┐
│  iOS App (SwiftUI)                                              │
│  • Session 列表                                                  │
│  • 确认/拒绝 Sheet                                               │
│  • 设置页                                                        │
└──────────────┬──────────────────────────────────────────────────┘
               │  HTTP GET /api/sessions
               │  HTTP POST /api/sessions/:id/action
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Tailscale Mesh VPN                                             │
│  • 零信任内网穿透，手机与电脑在同一虚拟内网                         │
│  • 无需公网 IP，无需端口暴露                                      │
└──────────────┬──────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Node.js Server (cc-dashboard/server.js)                        │
│  • Port 7777                                                    │
│  • GET  /api/sessions        → 返回所有活跃 session 数据          │
│  • POST /api/sessions/:id/action → confirm / reject / sendMessage│
│  • 读取 ~/.claude/sessions/ 和 ~/.claude/projects/               │
└──────────────┬──────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  本地数据                                                        │
│  • ~/.claude/sessions/*.json     (session 元数据)               │
│  • ~/.claude/projects/*/*.jsonl  (transcript 记录)              │
└─────────────────────────────────────────────────────────────────┘
```

### 3.1 Server 端兼容性
**Server 端无需改动**，现有 API 已完全覆盖 MVP 需求：
- `GET /api/sessions` — 返回所有活跃 session 列表及完整状态
- `POST /api/sessions/:id/action` — body: `{ "action": "confirm" | "reject" }`

## 4. MVP 功能范围

### 4.1 必须包含（V1.0）

| 功能 | 说明 |
|---|---|
| Session 列表 | 展示所有活跃 session 的状态（执行中/等待确认/空闲）、工作目录、模型、运行时长 |
| 终端类型标识 | 区分 Terminal.app/iTerm2（🖥）和 VS Code（⚡），图标前置 |
| 远程确认/拒绝 | 点击等待确认的 session，从底部弹出 Sheet，显示 tool 详情，支持确认/拒绝 |
| 设置页 | 配置电脑的 Tailscale IP 地址和端口号（默认 7777） |
| 数据刷新 | 下拉刷新 + 定时轮询（默认 5 秒，等待确认的 session 缩短到 2 秒） |

### 4.2 后续版本（V2+）

| 功能 | 说明 |
|---|---|
| 查看对话内容 | 打开 session 的详细页，查看最近消息历史 |
| 发送消息 | 在手机上直接向 session 发送文本消息 |
| 推送通知 | 当 session 进入"等待确认"状态时，推送通知到手机 |
| Context 可视化 | 展示 context window 占用率分布（消息/系统/空闲） |
| Token 统计 | 显示累计 input/output/cache 消耗 |

## 5. UI 设计

### 5.1 整体风格
- 深色科技主题，延续 web dashboard 的视觉风格
- 霓虹青/蓝/紫色系配色
- 毛玻璃效果卡片

### 5.2 Session 列表页

```
┌─────────────────────────────────┐
│ Claude Sessions           ⚙️    │
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ 🖥 ybt-claude           ●    │ │  ← 终端图标前置
│ │ /Users/kane/workspace/ybt    │ │
│ │ ● 等待确认  sonnet-4-6  42m  │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ ⚡ cc-dashboard          ●    │ │
│ │ /Users/kane/workspace/cc...  │ │
│ │ ● 执行中    sonnet-4-6  12m  │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ 🖥 gfdr-server           ○    │ │
│ │ /Users/kane/workspace/gfdr   │ │
│ │ ○ 空闲      opus-4-6    2h   │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

**排序规则**：等待确认 > 执行中 > 空闲，同状态按运行时长降序。

**卡片信息层级**：
1. 终端图标（🖥 蓝色 / ⚡ 紫色）+ Session 名称 + 状态点（最右）
2. 工作目录路径（截断显示）
3. 标签行：状态文字 + 模型 + 运行时长

### 5.3 确认操作 Sheet

```
┌─────────────────────────────────┐
│                                 │
│  ═══════════════════            │  ← 拖拽指示条
│  🖥 Terminal  ybt-claude        │
│  等待确认操作                    │
│  ┌───────────────────────────┐ │
│  │ Tool: Bash                │ │
│  │ Command:                  │ │
│  │ rm -rf node_modules       │ │
│  └───────────────────────────┘ │
│  ┌──────────┐  ┌──────────┐   │
│  │   拒绝   │  │   确认   │   │
│  └──────────┘  └──────────┘   │
└─────────────────────────────────┘
```

**交互**：
- 点击等待确认的 session 卡片触发 Sheet
- Sheet 从底部滑出，支持手势拖拽关闭
- 确认/拒绝按钮点击后显示 loading，成功后关闭 Sheet 并刷新列表
- 拒绝按钮为红色，确认按钮为绿色

### 5.4 设置页

```
┌─────────────────────────────────┐
│ 设置                     完成    │
├─────────────────────────────────┤
│                                 │
│ 服务器地址                      │
│ ┌─────────────────────────────┐ │
│ │ 100.64.0.1               ▶  │ │
│ └─────────────────────────────┘ │
│                                 │
│ 端口号                          │
│ ┌─────────────────────────────┐ │
│ │ 7777                     ▶  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                 │
│ 测试连接                        │
│ 自动刷新间隔                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                 │
│ 关于                            │
│ 版本 1.0.0                      │
└─────────────────────────────────┘
```

## 6. 数据模型

### 6.1 Session（来自 `/api/sessions`）

```swift
struct Session: Codable, Identifiable {
    let id: String              // 短 ID，如 "c2c5ff5c-8125"
    let fullId: String          // 完整 session ID
    let pid: Int
    let status: SessionStatus   // running | waiting | idle
    let startTime: TimeInterval // 毫秒时间戳
    let workDir: String
    let model: String
    let contextUsed: Int        // 百分比
    let tokensInput: Int
    let tokensOutput: Int
    let recentMessages: [Message]
    let source: SessionSource   // terminal | vscode
    let pendingTools: [PendingTool]?
}

enum SessionStatus: String, Codable {
    case running = "running"
    case waiting = "waiting"
    case idle = "idle"
}

enum SessionSource: String, Codable {
    case terminal = "terminal"
    case vscode = "vscode"
}

struct PendingTool: Codable {
    let id: String
    let name: String
    let input: [String: String]?
}
```

### 6.2 API 请求/响应

```swift
// GET /api/sessions → SessionListResponse
struct SessionListResponse: Codable {
    let timestamp: String
    let sessions: [Session]
}

// POST /api/sessions/:id/action
struct ActionRequest: Codable {
    let action: String  // "confirm" | "reject"
}

struct ActionResponse: Codable {
    let success: Bool
    let method: String?  // e.g. "Terminal.app"
    let error: String?
}
```

## 7. 刷新策略

| 场景 | 策略 | 说明 |
|---|---|---|
| 列表页可见 | 轮询 5 秒/次 | 常规刷新频率 |
| 有等待确认的 session | 轮询 2 秒/次 | 加快响应速度 |
| 用户下拉 | 立即刷新 | 手动触发 |
| App 后台 | 暂停轮询 | 节省电量和流量 |
| App 从后台恢复 | 立即刷新 | 数据同步 |

## 8. 错误处理

| 场景 | 处理方式 |
|---|---|
| 网络不可达（Tailscale 未连接） | 列表页显示"无法连接到服务器"提示，提供"打开 Tailscale"快捷入口 |
| Server 无响应 | 重试 3 次后提示，保留上次成功数据并显示"数据可能已过时" |
| Session 已结束 | 确认/拒绝时返回 410，提示"该 session 已结束"并从列表移除 |
| 确认操作失败 | Sheet 内显示错误信息，不关闭，允许重试 |
| 配置错误（IP/端口） | 设置页"测试连接"按钮提供即时验证 |

## 9. 项目结构

```
cc-dashboard-ios/
├── cc-dashboard-ios.xcodeproj
├── cc-dashboard-ios/
│   ├── App/
│   │   └── cc_dashboard_iosApp.swift    # @main 入口
│   ├── Views/
│   │   ├── SessionListView.swift        # 列表页
│   │   ├── SessionCardView.swift        # 单个 session 卡片
│   │   ├── ConfirmSheetView.swift       # 确认操作 Sheet
│   │   └── SettingsView.swift           # 设置页
│   ├── Models/
│   │   ├── Session.swift                # 数据模型
│   │   └── API.swift                    # API 请求封装
│   ├── Services/
│   │   ├── DashboardAPI.swift           # HTTP 客户端
│   │   └── SettingsStore.swift          # UserDefaults 配置存储
│   └── Assets/
│       └── Assets.xcassets/
```

## 10. 开发环境

- **Xcode** 16+
- **iOS** 17+（SwiftUI 现代特性）
- **Swift** 6
- **依赖管理**：Swift Package Manager（零第三方依赖，保持轻量）

## 11. 后续 Roadmap

### V1.1
- 推送通知：当 session 进入 waiting 状态时发送通知

### V1.2
- Session 详情页：查看最近消息历史

### V1.3
- 发送消息：在手机上直接向 session 发送文本指令

### V2.0
- Context 可视化图表
- Token 消耗统计
- Widget 小组件支持
