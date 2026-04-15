# Dashboard 实时消息监控与发送 实现计划

> **面向自动化执行者：** 必须使用子技能 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐条执行任务。步骤使用复选框（`- [ ]`）语法进行跟踪。

**目标：** 在浮动卡片内实现实时聊天面板：通过 SSE 接收 transcript 新增消息，并通过 POST action 向 Terminal.app / iTerm2 中的 session 发送文本消息。

**架构：** 后端用原生 HTTP SSE 推送 transcript 增量，扩展现有 AppleScript TTY 注入支持文本发送；前端用原生 EventSource 接收消息并渲染聊天气泡。

**技术栈：** Node.js (http)、原生 JavaScript、Tailwind CSS、AppleScript

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `server.js` | 新增 SSE `/stream` 端点；扩展 `POST /action` 支持 `sendMessage`；封装 transcript 解析与 SSE 推送逻辑 |
| `index.html` | 新增聊天面板 UI（消息列表 + 输入框）；SSE 连接与断开管理；发送消息前端逻辑 |

---

## 任务 1：后端 —— 添加读取 transcript 末尾 N 行的辅助函数

**文件：**
- 修改：`server.js`

- [ ] **步骤 1：在 `parseTranscript` 函数上方添加 `readTranscriptTail` 函数**

在 `function parseTranscript` 之前插入：

```javascript
/**
 * 读取 transcript 文件末尾 N 行
 */
function readTranscriptTail(transcriptPath, maxLines = 50) {
    if (!transcriptPath || !fs.existsSync(transcriptPath)) return [];
    try {
        const content = fs.readFileSync(transcriptPath, 'utf8');
        const allLines = content.split('\n').filter(l => l.trim());
        return allLines.slice(-maxLines);
    } catch (e) {
        return [];
    }
}
```

- [ ] **步骤 2：提交代码**

```bash
git add server.js
git commit -m "feat: 添加 readTranscriptTail 辅助函数，用于 SSE 初始历史消息"
```

---

## 任务 2：后端 —— 添加 SSE 端点 `/api/sessions/:id/stream`

**文件：**
- 修改：`server.js`

- [ ] **步骤 1：在 HTTP 服务器作用域内添加 `sendSSE` 辅助函数**

在 `http.createServer` 内部的 `const jsonHeaders = ...` 之后添加：

```javascript
function sendSSE(res, event, data) {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}
```

- [ ] **步骤 2：在静态文件处理器之前添加 `streamMatch` 路由**

在现有的 `actionMatch` 代码块之后（`let filePath = ...` 之前）插入：

```javascript
    // GET /api/sessions/:id/stream  SSE 端点
    const streamMatch = req.url.match(/^\/api\/sessions\/([^/]+)\/stream$/);
    if (streamMatch && req.method === 'GET') {
        const sessionId = streamMatch[1];
        const allSessions = getSessions();
        const session = allSessions.find(s =>
            s.sessionId === sessionId ||
            s.sessionId?.split('-').slice(0, 2).join('-') === sessionId
        );

        if (!session) {
            res.writeHead(404, jsonHeaders);
            res.end(JSON.stringify({ success: false, error: 'Session not found' }));
            return;
        }

        const transcriptPath = getTranscriptPath(session);
        let lastLines = readTranscriptTail(transcriptPath, 50);
        let lastLineCount = lastLines.length;

        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*'
        });

        // 发送初始历史消息
        const metadataTypes = ['permission-mode', 'agent-name', 'custom-title', 'file-history-snapshot'];
        const skipCmd = (c) => typeof c === 'string' && (
            c.includes('<command-name>') ||
            c.includes('<local-command-stdout>') ||
            c.includes('<local-command-caveat>') ||
            c.includes('<bash-stdout>') ||
            c.includes('<bash-input>')
        );

        for (const line of lastLines) {
            try {
                const entry = JSON.parse(line);
                if (entry.type !== 'user' && entry.type !== 'assistant') continue;
                if (entry.type === 'user' && skipCmd(entry.message?.content)) continue;
                const text = extractContent(entry);
                if (text && text.trim()) {
                    sendSSE(res, 'message', {
                        type: entry.type,
                        content: text.substring(0, 500),
                        time: formatTime(entry.timestamp)
                    });
                }
            } catch (e) {}
        }

        // 心跳定时器
        const heartbeat = setInterval(() => {
            if (!res.writableEnded) {
                sendSSE(res, 'ping', {});
            }
        }, 15000);

        // 文件监听定时器
        const watcher = setInterval(() => {
            if (!fs.existsSync(transcriptPath)) return;
            try {
                const content = fs.readFileSync(transcriptPath, 'utf8');
                const allLines = content.split('\n').filter(l => l.trim());
                if (allLines.length < lastLineCount) {
                    // 文件被截断或清空：重新发送末尾
                    lastLines = allLines.slice(-50);
                    lastLineCount = lastLines.length;
                    return;
                }
                if (allLines.length > lastLineCount) {
                    const newLines = allLines.slice(lastLineCount);
                    lastLineCount = allLines.length;
                    for (const line of newLines) {
                        try {
                            const entry = JSON.parse(line);
                            if (entry.type !== 'user' && entry.type !== 'assistant') continue;
                            if (entry.type === 'user' && skipCmd(entry.message?.content)) continue;
                            const text = extractContent(entry);
                            if (text && text.trim()) {
                                sendSSE(res, 'message', {
                                    type: entry.type,
                                    content: text.substring(0, 500),
                                    time: formatTime(entry.timestamp)
                                });
                            }
                        } catch (e) {}
                    }
                }
            } catch (e) {}
        }, 1000);

        req.on('close', () => {
            clearInterval(watcher);
            clearInterval(heartbeat);
            if (!res.writableEnded) res.end();
        });
        return;
    }
```

- [ ] **步骤 3：手动冒烟测试**

启动服务器：
```bash
node server.js &
```

测试不存在的 session：
```bash
curl -N http://localhost:7777/api/sessions/unknown/stream
```
预期结果：`{"success":false,"error":"Session not found"}`

测试真实 session（将 `<real-id>` 替换为 `/api/sessions` 返回的真实短 ID）：
```bash
curl -N http://localhost:7777/api/sessions/<real-id>/stream
```
预期结果：流式连接建立，先输出最近 50 条消息的 `data: {"type":"user",...}`，然后保持等待。

关闭后台服务器：
```bash
kill %1
```
或
```bash
kill $(lsof -ti:7777)
```

- [ ] **步骤 4：提交代码**

```bash
git add server.js
git commit -m "feat: 添加 SSE /api/sessions/:id/stream 端点"
```

---

## 任务 3：后端 —— 扩展 POST /action 支持 sendMessage

**文件：**
- 修改：`server.js`（第 468-502 行附近）

- [ ] **步骤 1：更新 action 校验逻辑，接受 sendMessage**

找到以下代码块：
```javascript
                if (action !== 'confirm' && action !== 'reject') {
                    res.writeHead(400, jsonHeaders);
                    res.end(JSON.stringify({ success: false, error: 'action must be confirm or reject' }));
                    return;
                }
```

替换为：
```javascript
                const { action, text } = JSON.parse(body || '{}');
                if (action !== 'confirm' && action !== 'reject' && action !== 'sendMessage') {
                    res.writeHead(400, jsonHeaders);
                    res.end(JSON.stringify({ success: false, error: 'action must be confirm, reject or sendMessage' }));
                    return;
                }
                if (action === 'sendMessage' && (!text || !text.trim())) {
                    res.writeHead(400, jsonHeaders);
                    res.end(JSON.stringify({ success: false, error: 'text is required for sendMessage' }));
                    return;
                }
```

- [ ] **步骤 2：替换 sendToTTY 调用块以处理 sendMessage**

找到以下代码：
```javascript
                // Claude Code 权限菜单：1 = Yes（确认一次），3 = No（拒绝）
                let input = action === 'confirm' ? '1' : '3';
                let result = sendKeystrokeToTerminal(ttyName, input);

                // 若菜单方式失败，回退到 y/n（部分旧版或简单确认模式）
                if (!result.success) {
                    input = action === 'confirm' ? 'y' : 'n';
                    result = sendKeystrokeToTerminal(ttyName, input);
                }
                res.writeHead(result.success ? 200 : 500, jsonHeaders);
                res.end(JSON.stringify(result));
```

替换为：
```javascript
                let result;
                if (action === 'sendMessage') {
                    result = sendKeystrokeToTerminal(ttyName, text.trim() + '\r');
                } else {
                    // Claude Code 权限菜单：1 = Yes（确认一次），3 = No（拒绝）
                    let input = action === 'confirm' ? '1' : '3';
                    result = sendKeystrokeToTerminal(ttyName, input);
                    if (!result.success) {
                        input = action === 'confirm' ? 'y' : 'n';
                        result = sendKeystrokeToTerminal(ttyName, input);
                    }
                }
                res.writeHead(result.success ? 200 : 500, jsonHeaders);
                res.end(JSON.stringify(result));
```

- [ ] **步骤 3：手动测试 sendMessage**

启动服务器：
```bash
node server.js &
```

从 `/api/sessions` 中获取一个运行在 Terminal.app 或 iTerm2 中的 session 短 ID，然后执行：
```bash
curl -X POST http://localhost:7777/api/sessions/<id>/action \
  -H "Content-Type: application/json" \
  -d '{"action":"sendMessage","text":"/help"}'
```

预期结果（如果找到 Terminal/iTerm 窗口）：`{"success":true,"method":"Terminal.app"}` 或 `{"success":true,"method":"iTerm.app"}`

检查实际终端标签页：`/help` 应该被输入并执行。

关闭服务器。

- [ ] **步骤 4：提交代码**

```bash
git add server.js
git commit -m "feat: 扩展 POST /action 支持 sendMessage，通过 AppleScript 注入 TTY"
```

---

## 任务 4：前端 —— 在浮动卡片中添加聊天面板 HTML/CSS

**文件：**
- 修改：`index.html`

- [ ] **步骤 1：在 `floatSession` 的 `renderPendingConfirmation` 之后插入聊天面板**

在 `floatSession` 的 HTML 模板中找到这行：
```javascript
                            ${renderPendingConfirmation(session)}
```

紧接其后插入：
```javascript
                            ${renderChatPanel(session)}
```

- [ ] **步骤 2：在 `renderContextBreakdown` 之前添加 `renderChatPanel` 函数**

插入以下代码：
```javascript
        function renderChatPanel(session) {
            const disabledHint = session.source === 'terminal' ? '' :
                `<p class="text-[10px] text-red-400 mt-1">该 session 不在 Terminal.app 或 iTerm2 中，无法远程发送消息</p>`;
            return `
                <div class="mb-4 rounded-xl border border-white/10 bg-white/5 p-3">
                    <div class="flex items-center justify-between mb-2 cursor-pointer" onclick="toggleChat('${session.id}')">
                        <span class="text-xs font-semibold text-gray-300">实时对话</span>
                        <span class="text-[10px] text-gray-500" id="chat-badge-${session.id}">点击展开</span>
                    </div>
                    <div id="chat-panel-${session.id}" class="hidden">
                        <div id="chat-msgs-${session.id}" class="h-48 overflow-y-auto space-y-2 pr-1 mb-2"></div>
                        <div class="flex gap-2">
                            <input
                                id="chat-input-${session.id}"
                                type="text"
                                class="flex-1 bg-black/20 border border-white/10 rounded px-2 py-1.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-cyan-500/50"
                                placeholder="输入消息后按回车发送..."
                                onkeydown="if(event.key==='Enter')sendChat('${session.id}')"
                            />
                            <button
                                onclick="sendChat('${session.id}')"
                                class="px-3 py-1.5 rounded text-xs font-medium bg-cyan-500/20 border border-cyan-500/40 text-cyan-400 hover:bg-cyan-500/30 transition-all"
                            >发送</button>
                        </div>
                        ${disabledHint}
                    </div>
                </div>
            `;
        }

        function toggleChat(sessionId) {
            const panel = document.getElementById(`chat-panel-${sessionId}`);
            if (!panel) return;
            const isHidden = panel.classList.contains('hidden');
            if (isHidden) {
                panel.classList.remove('hidden');
                startChatStream(sessionId);
            } else {
                panel.classList.add('hidden');
                stopChatStream(sessionId);
            }
        }
```

- [ ] **步骤 3：在 `<style>` 中添加聊天气泡样式**

在 `<style>` 区域的消息类附近（大约第 343 行左右）添加：

```css
        .chat-msg-user {
            background: rgba(0, 245, 255, 0.08);
            border: 1px solid rgba(0, 245, 255, 0.25);
            border-radius: 8px;
            border-bottom-right-radius: 2px;
        }
        .chat-msg-assistant {
            background: rgba(184, 41, 247, 0.08);
            border: 1px solid rgba(184, 41, 247, 0.25);
            border-radius: 8px;
            border-bottom-left-radius: 2px;
        }
```

- [ ] **步骤 4：提交代码**

```bash
git add index.html
git commit -m "feat: 在浮动卡片中添加聊天面板 UI"
```

---

## 任务 5：前端 —— 实现 SSE 连接与消息渲染

**文件：**
- 修改：`index.html`

- [ ] **步骤 1：在 `renderChatPanel` 之前添加 SSE 连接管理与消息追加逻辑**

插入以下代码：
```javascript
        const chatStreams = {}; // sessionId -> EventSource

        function startChatStream(sessionId) {
            if (chatStreams[sessionId]) return;
            const es = new EventSource(`/api/sessions/${sessionId}/stream`);
            chatStreams[sessionId] = es;

            es.addEventListener('message', (e) => {
                try {
                    const msg = JSON.parse(e.data);
                    appendChatMessage(sessionId, msg);
                } catch (err) {}
            });

            es.addEventListener('error', () => {
                // 断线重连由浏览器自动处理；若面板已关闭，由 stopChatStream 清理
            });
        }

        function stopChatStream(sessionId) {
            const es = chatStreams[sessionId];
            if (es) {
                es.close();
                delete chatStreams[sessionId];
            }
        }

        function appendChatMessage(sessionId, msg) {
            const container = document.getElementById(`chat-msgs-${sessionId}`);
            if (!container) return;
            const isUser = msg.type === 'user';
            const html = `
                <div class="flex ${isUser ? 'justify-end' : 'justify-start'}">
                    <div class="max-w-[85%] px-2.5 py-1.5 text-xs ${isUser ? 'chat-msg-user text-cyan-100' : 'chat-msg-assistant text-purple-100'}">
                        <div class="whitespace-pre-wrap break-words">${escHtml(msg.content)}</div>
                        <div class="text-[10px] mt-0.5 opacity-60 text-right">${escHtml(msg.time || '刚刚')}</div>
                    </div>
                </div>
            `;
            container.insertAdjacentHTML('beforeend', html);
            container.scrollTop = container.scrollHeight;

            const badge = document.getElementById(`chat-badge-${sessionId}`);
            if (badge) badge.textContent = `${container.children.length} 条消息`;
        }
```

- [ ] **步骤 2：确保关闭浮动卡片时同步关闭 SSE**

找到 `closeFloat` 函数。在其移除浮动卡片、恢复原始卡片之后，添加：

```javascript
            stopChatStream(sessionId);
```

插入位置：在 `if (backdrop) backdrop.classList.remove('active');` 代码块之后。

- [ ] **步骤 3：手动冒烟测试**

启动服务器：
```bash
node server.js &
```

浏览器打开 `http://localhost:7777`，点击任意活跃 session 卡片，点击「实时对话」展开。
预期结果：
- 面板展开
- Network 标签页中出现 EventSource 连接到 `/stream`
- 1-2 秒内显示历史消息

关闭浮动卡片。
预期结果：Network 标签页中该 SSE 连接断开。

- [ ] **步骤 4：提交代码**

```bash
git add index.html
git commit -m "feat: 添加 SSE 客户端与聊天消息渲染逻辑"
```

---

## 任务 6：前端 —— 实现发送聊天消息

**文件：**
- 修改：`index.html`

- [ ] **步骤 1：在 `startChatStream` 之前添加 `sendChat` 函数**

插入以下代码：
```javascript
        async function sendChat(sessionId) {
            const input = document.getElementById(`chat-input-${sessionId}`);
            if (!input) return;
            const text = input.value.trim();
            if (!text) return;

            // 乐观地在本地显示用户消息
            appendChatMessage(sessionId, { type: 'user', content: text, time: '刚刚' });

            input.value = '';
            input.disabled = true;

            try {
                const res = await fetch(`/api/sessions/${sessionId}/action`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'sendMessage', text })
                });
                const data = await res.json();
                if (!data.success) {
                    appendChatMessage(sessionId, {
                        type: 'assistant',
                        content: `发送失败：${data.error}`,
                        time: '刚刚'
                    });
                }
                // 发送成功时，等待 SSE 推送 Claude 的真实回复
            } catch (e) {
                appendChatMessage(sessionId, {
                    type: 'assistant',
                    content: `网络错误：${e.message}`,
                    time: '刚刚'
                });
            } finally {
                input.disabled = false;
                input.focus();
            }
        }
```

- [ ] **步骤 2：确认乐观消息样式**

现有的 `appendChatMessage` 已正确为 `user` 类型消息应用青色气泡样式，无需额外修改。

- [ ] **步骤 3：端到端测试**

1. 启动服务器：
   ```bash
   node server.js &
   ```
2. 浏览器打开 `http://localhost:7777`
3. 点击一个 **Terminal.app** 或 **iTerm2** 中的 session
4. 展开「实时对话」
5. 输入 `hello` 并点击「发送」

预期结果：
- Dashboard 聊天面板立即显示青色用户气泡
- 实际终端标签页中显示 `hello` 被输入并执行
- 数秒内 SSE 推送 Claude 的回复到 dashboard

关闭服务器。

- [ ] **步骤 4：提交代码**

```bash
git add index.html
git commit -m "feat: 实现聊天消息发送与乐观 UI 反馈"
```

---

## 自查

**规范覆盖检查：**
- ✅ SSE `/stream` 端点 → 任务 2
- ✅ 通过 POST action 发送消息 → 任务 3
- ✅ 聊天面板 UI（消息列表 + 输入框）→ 任务 4
- ✅ SSE 客户端连接管理 → 任务 5
- ✅ 发送消息前端逻辑 → 任务 6
- ✅ Terminal.app / iTerm2 兼容性 → 任务 3（复用现有 `sendKeystrokeToTerminal`）
- ✅ 不支持终端的提示 → 任务 4（`disabledHint`）
- ✅ 心跳 + 自动重连 → 任务 2（心跳定时器，EventSource 原生重连）
- ✅ 关闭卡片时断开流 → 任务 5（`closeFloat` 中调用 `stopChatStream`）

**占位符扫描：**
- 未发现 TBD/TODO/"后续实现" 等占位内容
- 所有代码块均包含完整可运行的代码
- 所有步骤均包含精确的命令与预期输出

**类型一致性：**
- `sendKeystrokeToTerminal` 函数签名未改变（`ttyName, text`）
- `sendToTTY` 仍用于 confirm/reject；sendMessage 在任务 3 中直接调用 `sendKeystrokeToTerminal` —— 正确
- 任务 2 中复用现有的 `extractContent` 函数
- 任务 4-6 中复用现有的 `escHtml` 函数
