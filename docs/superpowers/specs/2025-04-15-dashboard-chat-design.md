# Dashboard 实时消息监控与发送设计文档

## 背景

当前 cc-dashboard v1.0.0 已支持：
- 展示活跃 Session 列表、状态、Context 占用、Token 统计
- 展示最近 10 条静态交互消息
- 对处于 waiting 状态的 session 发送 confirm/reject

本迭代目标：
1. **实时监控 session 中的消息流**（类似聊天窗口实时滚动）
2. **在 dashboard 中向 session 发送普通文本消息**

## 约束

- 发送消息依赖 AppleScript 向 Terminal.app / iTerm2 注入按键
- VS Code 集成终端、Warp、Tabby 等第三方终端暂不支持发送
- 保持项目极简风格：单文件 HTML + 一个 server.js，尽量不引入新依赖

## 方案选择

采用 **SSE (Server-Sent Events) + POST** 方案：
- 监控：SSE 单向推送 transcript 新增内容，无额外 WebSocket 依赖
- 发送：扩展现有 POST /api/sessions/:id/action，新增 sendMessage action

## 架构

### 后端

#### 1. SSE 端点：`GET /api/sessions/:id/stream`

**连接流程：**
1. 根据 `:id` 查找 session（匹配完整 UUID 或短 ID）
2. 解析对应 transcript 路径
3. 记录当前文件行数 `lastLineCount`
4. 设置 `setInterval`（1 秒）检查文件大小/修改时间
5. 发现新增行时，逐行解析并推送有效消息

**推送格式：**
```text
event: message
data: {"type":"user","content":"帮我优化代码","time":"刚刚"}

event: message
data: {"type":"assistant","content":"好的，我来分析...","time":"刚刚"}
```

**过滤规则：**
- 只推送 `type === 'user'` 或 `type === 'assistant'` 的消息
- 过滤 `<command-name>`、`<local-command-stdout>`、`<bash-stdout>` 等命令注入内容
- `tool_result` 类型可视情况以 `system` 摘要形式推送（可选，首期可暂不推送）

**心跳：**
```text
event: ping
data: {}
```
- 每 15 秒一次，防止浏览器/代理超时断开

**断线清理：**
- `req.on('close', ...)` 中 `clearInterval` 并 `res.end()`

#### 2. 扩展 POST `/api/sessions/:id/action`

现有逻辑：
```json
{ "action": "confirm" }
{ "action": "reject" }
```

新增：
```json
{ "action": "sendMessage", "text": "帮我优化代码" }
```

**处理流程：**
1. 查找 session，校验进程存活
2. 获取 TTY 名称（`ps -o tty=`）
3. 调用 `sendKeystrokeToTerminal(ttyName, text + '\r')`
4. 返回结果：`{ success: true, method: 'iTerm.app' }` 或错误信息

**限制：**
- 若 `source !== 'terminal' && source !== 'vscode'`（当前 getSessionSource 只返回 terminal/vscode），但 VS Code 集成终端实际上也无法注入。因此更准确的限制是：AppleScript 找不到对应 TTY 窗口时直接返回错误。
- 文本长度无特殊限制，但建议前端限制在 2000 字符以内

### 前端

#### 1. 浮动卡片新增「实时对话」区域

在现有浮动卡片中，Context 分布区块上方插入一个可折叠的聊天面板：

```html
<!-- 折叠触发按钮 -->
<div onclick="toggleChat('session-id')">实时对话 (12 条)</div>

<!-- 聊天面板 -->
<div id="chat-session-id" class="chat-panel">
  <div class="chat-messages" id="chat-msgs-session-id"></div>
  <div class="chat-input-row">
    <input id="chat-input-session-id" placeholder="输入消息..." />
    <button onclick="sendChat('session-id')">发送</button>
  </div>
</div>
```

**消息样式：**
- user：右对齐，青色边框/背景
- assistant：左对齐，紫色边框/背景
- system/tool_result：居中，灰色小号字（可选）
- 每条消息带时间戳

#### 2. SSE 连接管理

```javascript
const es = new EventSource(`/api/sessions/${sessionId}/stream`);
es.addEventListener('message', e => {
  const msg = JSON.parse(e.data);
  appendChatMessage(sessionId, msg);
});
```

**生命周期：**
- 打开浮动卡片时建立 SSE 连接
- 关闭浮动卡片时 `es.close()`
- 浏览器断线后 `EventSource` 自动重连，无需额外代码

#### 3. 发送消息

```javascript
async function sendChat(sessionId) {
  const input = document.getElementById(`chat-input-${sessionId}`);
  const text = input.value.trim();
  if (!text) return;

  input.disabled = true;
  const res = await fetch(`/api/sessions/${sessionId}/action`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'sendMessage', text })
  });
  const data = await res.json();
  if (data.success) {
    input.value = '';
    // 用户消息不会立即出现在 dashboard，需等待 SSE 推送（1 秒内）
  } else {
    showError(sessionId, data.error);
  }
  input.disabled = false;
}
```

**不支持发送的场景：**
- 后端返回 `success: false` 且 error 包含"未找到 TTY"时
- 输入框变为禁用态，显示红色提示：
  > "该 session 不在 Terminal.app 或 iTerm2 中，无法远程发送消息。"

## 数据流

```
用户在前端输入消息
        ↓
POST /api/sessions/:id/action {action:'sendMessage', text}
        ↓
server.js → AppleScript → TTY → Claude CLI 进程
        ↓
Claude 回复并写入 transcript
        ↓
SSE /stream 检测到新增行 → 推送至浏览器
        ↓
前端聊天面板追加消息
```

## 错误处理

| 场景 | 行为 |
|------|------|
| SSE 断线 | EventSource 自动重连，3 秒后尝试 |
| session 关闭 | SSE 推送 `event: close`，前端关闭连接 |
| AppleScript 找不到窗口 | 显示红色提示，输入框禁用 |
| 文本为空 | 前端阻止发送 |
| 进程已退出 | POST 返回 400，SSE 推送 close |

## 边界情况

1. **并发 SSE 连接**：一个浏览器打开多个浮动卡片时，每个卡片独立维护一个 SSE 连接。server.js 无全局连接池，每个请求独立 `setInterval`。
2. **大 transcript 文件**：SSE 建立连接时只读取最后 N 行（如 50 行）作为初始历史，避免一次性推送过多。
3. **transcript 被 truncate/clear**：检测到文件行数减少时，视为文件重置，重新从头读取最后 50 行。

## 文件变更

- `server.js`：新增 `/stream` 端点，扩展 `sendKeystrokeToTerminal`，扩展 `POST /action`
- `index.html`：新增聊天面板 UI、SSE 连接逻辑、发送消息逻辑
- 无需新增 npm 依赖

## 验收标准

- [ ] 打开浮动卡片后，1 秒内建立 SSE，开始接收实时消息
- [ ] 在 Terminal.app / iTerm2 中的 session，可在 dashboard 发送消息，Claude 正常回复
- [ ] 发送消息后，dashboard 聊天面板在 2 秒内看到自己的消息和 Claude 的回复
- [ ] 关闭浮动卡片后，SSE 连接断开，浏览器 Network 中无残留连接
- [ ] 不支持发送的终端显示明确提示，按钮禁用
