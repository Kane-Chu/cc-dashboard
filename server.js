#!/usr/bin/env node

/**
 * Claude Code CLI Dashboard Server
 * Serves dashboard and provides real-time session data API
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 7777;
const CLAUDE_DIR = path.join(process.env.HOME || '/Users/kane', '.claude');
const SESSIONS_DIR = path.join(CLAUDE_DIR, 'sessions');
const PROJECTS_DIR = path.join(CLAUDE_DIR, 'projects');

/**
 * Read session files
 */
function getSessions() {
    const sessions = [];
    if (!fs.existsSync(SESSIONS_DIR)) return sessions;

    const files = fs.readdirSync(SESSIONS_DIR).filter(f => f.endsWith('.json'));
    for (const file of files) {
        try {
            const content = fs.readFileSync(path.join(SESSIONS_DIR, file), 'utf8');
            sessions.push(JSON.parse(content));
        } catch (e) {}
    }
    return sessions;
}

/**
 * Find transcript path for a session
 */
function getTranscriptPath(session) {
    const sessionId = session.sessionId;
    const cwd = session.cwd || '';
    // /Users/kane/foo → -Users-kane-foo，与 .claude/projects/ 目录命名一致，不能去掉开头的 -
    const projectPath = cwd.replace(/\//g, '-');
    const projectDir = path.join(PROJECTS_DIR, projectPath);

    if (fs.existsSync(projectDir)) {
        const transcriptFile = path.join(projectDir, `${sessionId}.jsonl`);
        if (fs.existsSync(transcriptFile)) return transcriptFile;
    }

    // Search all projects
    if (fs.existsSync(PROJECTS_DIR)) {
        for (const project of fs.readdirSync(PROJECTS_DIR)) {
            const transcriptFile = path.join(PROJECTS_DIR, project, `${sessionId}.jsonl`);
            if (fs.existsSync(transcriptFile)) return transcriptFile;
        }
    }
    return null;
}

/**
 * Parse transcript for stats
 */
function parseTranscript(transcriptPath) {
    const stats = {
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalCacheRead: 0,
        totalCacheCreate: 0,
        lastInputTokens: 0,        // 最后一条 assistant 消息的完整输入量，用于 context window 使用率
        estimatedMessageTokens: 0, // 从消息文本估算的对话部分 token 数（字符数 / 3.5）
        recentMessages: [],
        lastActivityTime: null,
        lastMessageType: null,
        lastMessageStopReason: null,
        isWaitingForTool: false,
        hasTurnCompleted: false,
        pendingTools: []   // 待确认的 tool_use 块
    };

    if (!transcriptPath || !fs.existsSync(transcriptPath)) return stats;

    try {
        // 读取完整文件，确保 token 累计统计不遗漏历史记录
        const content = fs.readFileSync(transcriptPath, 'utf8');
        const lines = content.split('\n').filter(l => l.trim());

        // Parse all lines to get total tokens and find recent messages
        for (const line of lines) {
            try {
                const entry = JSON.parse(line);

                // Track last activity time
                if (entry.timestamp) {
                    if (!stats.lastActivityTime || new Date(entry.timestamp) > new Date(stats.lastActivityTime)) {
                        stats.lastActivityTime = entry.timestamp;
                    }
                }

                if (entry.type === 'assistant' && entry.message?.usage) {
                    const u = entry.message.usage;
                    stats.totalInputTokens += u.input_tokens || 0;
                    stats.totalOutputTokens += u.output_tokens || 0;
                    stats.totalCacheRead += u.cache_read_input_tokens || 0;
                    stats.totalCacheCreate += u.cache_creation_input_tokens || 0;
                    // 只在 usage 有效（非零）时更新，跳过流式中断、sidechain 等产生的全零消息
                    // context window 实际占用 = input + cache_read + cache_creation，三者缺一不可
                    const totalCtxTokens = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
                    if (totalCtxTokens > 0) {
                        stats.lastInputTokens = totalCtxTokens;
                    }
                }
            } catch (e) {}
        }

        // 估算对话消息部分的 token 数：遍历所有 user/assistant 消息的文本内容
        // 包含工具调用输出、bash 结果等所有注入内容，以字符数 / 3.5 估算
        let totalMessageChars = 0;
        for (const line of lines) {
            try {
                const entry = JSON.parse(line);
                if (entry.type !== 'user' && entry.type !== 'assistant') continue;
                const c = entry.message?.content;
                if (typeof c === 'string') {
                    totalMessageChars += c.length;
                } else if (Array.isArray(c)) {
                    for (const block of c) {
                        if (block.type === 'text') totalMessageChars += block.text?.length || 0;
                        else if (block.type === 'tool_result') {
                            // tool result 内容可以是字符串或数组
                            const r = block.content;
                            if (typeof r === 'string') totalMessageChars += r.length;
                            else if (Array.isArray(r)) {
                                for (const b of r) {
                                    if (b.type === 'text') totalMessageChars += b.text?.length || 0;
                                }
                            }
                        }
                    }
                }
            } catch (e) {}
        }
        stats.estimatedMessageTokens = Math.round(totalMessageChars / 3.5);

        // Get recent messages - 从末尾向前扫，直到凑够 10 条真实对话消息
        for (let i = lines.length - 1; i >= 0 && stats.recentMessages.length < 10; i--) {
            try {
                const entry = JSON.parse(lines[i]);
                if (entry.type !== 'user' && entry.type !== 'assistant') continue;

                // 跳过命令类注入内容（非真实用户输入）
                if (entry.type === 'user' && entry.message?.content) {
                    const c = entry.message.content;
                    if (typeof c === 'string' && (
                        c.includes('<command-name>') ||
                        c.includes('<local-command-stdout>') ||
                        c.includes('<local-command-caveat>') ||
                        c.includes('<bash-stdout>') ||
                        c.includes('<bash-input>')
                    )) continue;
                }

                const content = extractContent(entry);
                if (content && content.trim()) {
                    stats.recentMessages.push({
                        type: entry.type,
                        content: content.substring(0, 100),
                        time: formatTime(entry.timestamp)
                    });
                }
            } catch (e) {}
        }

        // Check last message to determine status
        // Look for the last meaningful message (assistant/user/system) and check for turn_completion
        if (lines.length > 0) {
            try {
                // Find the last meaningful message, skipping metadata entries
                const metadataTypes = ['permission-mode', 'agent-name', 'custom-title', 'file-history-snapshot'];
                for (let i = lines.length - 1; i >= 0; i--) {
                    const entry = JSON.parse(lines[i]);

                    // Track turn completion - indicates a round is finished
                    if (entry.type === 'system' && entry.subtype === 'turn_duration') {
                        stats.hasTurnCompleted = true;
                    }

                    // Skip metadata types that don't represent actual conversation
                    if (metadataTypes.includes(entry.type)) {
                        continue;
                    }

                    // Skip local command messages (not real user input)
                    if (entry.type === 'user' && entry.message?.content) {
                        const content = entry.message.content;
                        if (typeof content === 'string') {
                            // Skip /command inputs, bash mode commands, and their outputs
                            if (content.includes('<command-name>') ||
                                content.includes('<local-command-stdout>') ||
                                content.includes('<local-command-caveat>') ||
                                content.includes('<bash-stdout>') ||
                                content.includes('<bash-input>')) {
                                continue;
                            }
                        }
                    }

                    // Check last assistant/user message
                    // From back to front, find the most recent conversation message
                    // Update if we found a newer message (we're going backwards, so first found is newest)
                    if (!stats.lastMessageType && (entry.type === 'assistant' || entry.type === 'user')) {
                        stats.lastMessageType = entry.type;
                        if (entry.type === 'assistant' && entry.message) {
                            stats.lastMessageStopReason = entry.message.stop_reason;
                            stats.isWaitingForTool = entry.message.stop_reason === 'tool_use';

                            // 提取 tool_use 块，用于在 dashboard 展示待确认内容
                            if (stats.isWaitingForTool && Array.isArray(entry.message.content)) {
                                stats.pendingTools = entry.message.content
                                    .filter(b => b.type === 'tool_use')
                                    .map(b => ({ id: b.id, name: b.name, input: b.input }));
                            }
                        }
                        break;
                    }
                }
            } catch (e) {}
        }
    } catch (e) {}

    return stats;
}

function extractContent(entry) {
    if (!entry.message?.content) return null;
    const c = entry.message.content;
    if (typeof c === 'string') return c;
    if (Array.isArray(c)) {
        return c.filter(x => x.type === 'text').map(x => x.text).join(' ');
    }
    return null;
}

function formatTime(ts) {
    if (!ts) return '';
    const diff = Math.floor((Date.now() - new Date(ts).getTime()) / 1000);
    if (diff < 60) return '刚刚';
    if (diff < 3600) return `${Math.floor(diff / 60)}分钟前`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}小时前`;
    return `${Math.floor(diff / 86400)}天前`;
}

function isRunning(pid) {
    try {
        process.kill(pid, 0);
        return true;
    } catch (e) {
        return false;
    }
}

/**
 * Get session source by checking process command line
 */
function getSessionSource(pid) {
    try {
        const { execSync } = require('child_process');
        const output = execSync(`ps -p ${pid} -o args= 2>/dev/null`, { encoding: 'utf8' });
        if (output.includes('.vscode/extensions/anthropic.claude-code')) {
            return 'vscode';
        }
    } catch (e) {
        // ignore
    }
    return 'terminal';
}

/**
 * Collect all session data
 */
function collectData() {
    const sessions = getSessions();
    const maxContext = 200000; // 200K tokens
    const activeSessions = [];

    for (const session of sessions) {
        if (!isRunning(session.pid)) continue;

        const transcriptPath = getTranscriptPath(session);
        const stats = parseTranscript(transcriptPath);
        const startedAt = session.startedAt || Date.now();

        // 用最后一条 assistant 消息的 input_tokens 计算当前 context window 占用率
        // 这代表当前这一轮对话实际占用的上下文大小，比累计值更准确
        // 若还没有 assistant 消息则回退到累计值
        const currentTokens = stats.lastInputTokens > 0 ? stats.lastInputTokens : stats.totalInputTokens;
        const contextPercentage = Math.min(Math.round((currentTokens / maxContext) * 100), 100);

        // Determine status based on last message type and stop reason
        // Priority: waiting for tool > running > idle
        let status = 'idle';

        if (stats.isWaitingForTool) {
            // Assistant is waiting for tool execution result
            status = 'waiting';
        } else if (stats.lastMessageType === 'user') {
            // User just sent a message, Claude is processing
            status = 'running';
        } else if (stats.lastMessageType === 'assistant') {
            // Assistant has responded - check if it's complete
            // If stop_reason is end_turn or stop_sequence, response is complete -> idle
            // If no stop_reason, might still be streaming -> running
            if (!stats.lastMessageStopReason) {
                status = 'running';
            }
            // Otherwise idle (response complete)
        }

        // 计算 context 分布（用于浮动卡片详情）
        const ctxTotal = currentTokens;
        const ctxMsg   = Math.min(stats.estimatedMessageTokens, ctxTotal); // 消息估算，不超过总量
        const ctxSys   = Math.max(0, ctxTotal - ctxMsg);                   // 系统/工具 = 总量 - 消息
        const ctxFree  = Math.max(0, maxContext - ctxTotal);                // 剩余空闲

        activeSessions.push({
            id: session.sessionId?.split('-').slice(0, 2).join('-') || 'unknown',
            fullId: session.sessionId,
            pid: session.pid,
            status: status,
            startTime: startedAt,
            workDir: session.cwd || '/unknown',
            model: session.model || 'claude-sonnet-4-6',
            contextUsed: contextPercentage,
            contextTotal: 100,
            tokensInput: stats.totalInputTokens,
            tokensOutput: stats.totalOutputTokens,
            recentMessages: stats.recentMessages,
            source: getSessionSource(session.pid),
            contextBreakdown: {
                total:    ctxTotal,
                messages: ctxMsg,
                system:   ctxSys,
                free:     ctxFree,
                maxContext
            },
            pendingTools: stats.pendingTools
        });
    }

    return {
        timestamp: new Date().toISOString(),
        sessions: activeSessions
    };
}

/**
 * 通过 AppleScript 向 Terminal.app / iTerm 的指定 TTY 标签页发送按键
 * macOS 13+ 已移除 TIOCSTI，PTY write 无法被目标进程读取，因此必须依赖终端模拟器转发
 */
function sendKeystrokeToTerminal(ttyName, text) {
    const { spawnSync } = require('child_process');
    const esc = s => s.replace(/"/g, '\\"');

    // 1. 尝试 Terminal.app
    const terminalScript = `
tell application "Terminal"
    repeat with w in windows
        set wid to id of w
        repeat with t in tabs of w
            try
                if tty of t is "${esc(ttyName)}" or tty of t is "/dev/${esc(ttyName)}" then
                    do script "echo dummy" in t
                    delay 0.05
                    tell application "System Events" to tell process "Terminal"
                        set frontmost to true
                        keystroke "${esc(text)}"
                        keystroke return
                    end tell
                    return "ok"
                end if
            end try
        end repeat
    end repeat
end tell
return "not_found"
`;
    const r1 = spawnSync('osascript', ['-e', terminalScript], { encoding: 'utf8', timeout: 5000 });
    if (r1.stdout?.trim() === 'ok') return { success: true, method: 'Terminal.app' };

    // 2. 尝试 iTerm.app
    const itermScript = `
tell application "iTerm2"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                try
                    set tt to (tty of s)
                    if tt is "${esc(ttyName)}" or tt is "/dev/${esc(ttyName)}" then
                        tell s to write text "${esc(text)}"
                        return "ok"
                    end if
                end try
            end repeat
        end repeat
    end repeat
end tell
return "not_found"
`;
    const r2 = spawnSync('osascript', ['-e', itermScript], { encoding: 'utf8', timeout: 5000 });
    if (r2.stdout?.trim() === 'ok') return { success: true, method: 'iTerm.app' };

    return {
        success: false,
        error: `未找到 TTY 为 ${ttyName} 的 Terminal.app / iTerm 窗口。VS Code 集成终端、Warp、Tabby 等暂不支持远程按键注入。`
    };
}

/**
 * 向目标进程发送确认/拒绝
 */
function sendToTTY(pid, action) {
    const { spawnSync } = require('child_process');
    const psResult = spawnSync('ps', ['-o', 'tty=', '-p', String(pid)], { encoding: 'utf8' });
    const ttyName = psResult.stdout.trim();
    if (!ttyName || ttyName === '??') {
        return { success: false, error: '该进程没有控制终端（可能是后台进程或 VS Code 集成终端）' };
    }

    // Claude Code 权限菜单：1 = Yes（确认一次），3 = No（拒绝）
    let input = action === 'confirm' ? '1' : '3';
    let result = sendKeystrokeToTerminal(ttyName, input);

    // 若菜单方式失败，回退到 y/n（部分旧版或简单确认模式）
    if (!result.success) {
        input = action === 'confirm' ? 'y' : 'n';
        result = sendKeystrokeToTerminal(ttyName, input);
    }
    return result;
}

/**
 * Serve static files and API
 */
const MIME_TYPES = {
    '.html': 'text/html',
    '.js': 'application/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.png': 'image/png',
    '.ico': 'image/x-icon'
};

const server = http.createServer((req, res) => {
    const jsonHeaders = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

    if (req.url === '/api/sessions') {
        res.writeHead(200, jsonHeaders);
        res.end(JSON.stringify(collectData()));
        return;
    }

    // POST /api/sessions/:id/action  { action: 'confirm' | 'reject' }
    const actionMatch = req.url.match(/^\/api\/sessions\/([^/]+)\/action$/);
    if (actionMatch && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            try {
                const { action } = JSON.parse(body || '{}');
                if (action !== 'confirm' && action !== 'reject') {
                    res.writeHead(400, jsonHeaders);
                    res.end(JSON.stringify({ success: false, error: 'action must be confirm or reject' }));
                    return;
                }

                const sessionId = actionMatch[1];
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
                if (!isRunning(session.pid)) {
                    res.writeHead(400, jsonHeaders);
                    res.end(JSON.stringify({ success: false, error: 'Session process is not running' }));
                    return;
                }

                const result = sendToTTY(session.pid, action);
                res.writeHead(result.success ? 200 : 500, jsonHeaders);
                res.end(JSON.stringify(result));
            } catch (e) {
                res.writeHead(400, jsonHeaders);
                res.end(JSON.stringify({ success: false, error: e.message }));
            }
        });
        return;
    }

    let filePath = req.url === '/' ? '/index.html' : req.url;
    filePath = path.join(__dirname, filePath);

    const ext = path.extname(filePath);
    const contentType = MIME_TYPES[ext] || 'text/plain';

    fs.readFile(filePath, (err, data) => {
        if (err) {
            res.writeHead(404);
            res.end('Not Found');
            return;
        }
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
    });
});

server.listen(PORT, () => {
    console.log(`Claude Code Dashboard running at http://localhost:${PORT}`);
    console.log(`API endpoint: http://localhost:${PORT}/api/sessions`);
});

module.exports = { server, collectData };
