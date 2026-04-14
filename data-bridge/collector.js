#!/usr/bin/env node

/**
 * Claude Code CLI Data Collector
 * Collects real-time session data from Claude Code CLI
 */

const fs = require('fs');
const path = require('path');

const CLAUDE_DIR = path.join(process.env.HOME || '/Users/kane', '.claude');
const SESSIONS_DIR = path.join(CLAUDE_DIR, 'sessions');
const PROJECTS_DIR = path.join(CLAUDE_DIR, 'projects');

/**
 * Read session files from ~/.claude/sessions/
 */
function getSessions() {
    const sessions = [];

    if (!fs.existsSync(SESSIONS_DIR)) {
        return sessions;
    }

    const files = fs.readdirSync(SESSIONS_DIR).filter(f => f.endsWith('.json'));

    for (const file of files) {
        try {
            const content = fs.readFileSync(path.join(SESSIONS_DIR, file), 'utf8');
            const sessionData = JSON.parse(content);
            sessions.push(sessionData);
        } catch (e) {
            console.error(`Error reading session file ${file}:`, e.message);
        }
    }

    return sessions;
}

/**
 * Get transcript path for a session
 */
function getTranscriptPath(session) {
    // Transcript is stored in project directory
    const sessionId = session.sessionId;
    const cwd = session.cwd || '';

    // Normalize cwd to project path
    const projectPath = cwd.replace(/\//g, '-').replace(/^-/, '');
    const projectDir = path.join(PROJECTS_DIR, projectPath);

    if (fs.existsSync(projectDir)) {
        const transcriptFile = path.join(projectDir, `${sessionId}.jsonl`);
        if (fs.existsSync(transcriptFile)) {
            return transcriptFile;
        }
    }

    // Try to find in all project directories
    if (fs.existsSync(PROJECTS_DIR)) {
        const projects = fs.readdirSync(PROJECTS_DIR);
        for (const project of projects) {
            const transcriptFile = path.join(PROJECTS_DIR, project, `${sessionId}.jsonl`);
            if (fs.existsSync(transcriptFile)) {
                return transcriptFile;
            }
        }
    }

    return null;
}

/**
 * Parse transcript and extract stats
 */
function parseTranscript(transcriptPath) {
    const stats = {
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalCacheRead: 0,
        totalCacheCreate: 0,
        messageCount: 0,
        recentMessages: []
    };

    if (!transcriptPath || !fs.existsSync(transcriptPath)) {
        return stats;
    }

    try {
        // Read last 50KB of transcript for recent messages
        const stat = fs.statSync(transcriptPath);
        const readSize = Math.min(stat.size, 50 * 1024);
        const buffer = Buffer.alloc(readSize);
        const fd = fs.openSync(transcriptPath, 'r');

        if (stat.size > readSize) {
            fs.readSync(fd, buffer, 0, readSize, stat.size - readSize);
        } else {
            fs.readSync(fd, buffer, 0, readSize, 0);
        }
        fs.closeSync(fd);

        const content = buffer.toString('utf8');
        const lines = content.split('\n').filter(l => l.trim());

        // Parse lines and get stats
        for (const line of lines) {
            try {
                const entry = JSON.parse(line);
                if (entry.type === 'assistant' && entry.message?.usage) {
                    const usage = entry.message.usage;
                    stats.totalInputTokens += usage.input_tokens || 0;
                    stats.totalOutputTokens += usage.output_tokens || 0;
                    stats.totalCacheRead += usage.cache_read_input_tokens || 0;
                    stats.totalCacheCreate += usage.cache_creation_input_tokens || 0;
                    stats.messageCount++;
                }
            } catch (e) {
                // Skip invalid lines
            }
        }

        // Get last 5 messages
        stats.recentMessages = getRecentMessages(lines.slice(-20), 5);

    } catch (e) {
        console.error(`Error parsing transcript ${transcriptPath}:`, e.message);
    }

    return stats;
}

/**
 * Get recent messages from transcript lines
 */
function getRecentMessages(lines, count) {
    const messages = [];

    for (let i = lines.length - 1; i >= 0 && messages.length < count; i--) {
        try {
            const entry = JSON.parse(lines[i]);
            if (entry.type === 'user' || entry.type === 'assistant') {
                const content = extractMessageContent(entry);
                if (content) {
                    messages.unshift({
                        type: entry.type,
                        content: content.substring(0, 100),
                        time: formatTimestamp(entry.timestamp)
                    });
                }
            }
        } catch (e) {
            // Skip invalid lines
        }
    }

    return messages;
}

/**
 * Extract message content
 */
function extractMessageContent(entry) {
    if (!entry.message) return null;

    const msg = entry.message;

    if (msg.content) {
        if (typeof msg.content === 'string') {
            return msg.content;
        }
        if (Array.isArray(msg.content)) {
            return msg.content
                .filter(c => c.type === 'text')
                .map(c => c.text)
                .join(' ');
        }
    }

    return null;
}

/**
 * Format timestamp to relative time
 */
function formatTimestamp(timestamp) {
    if (!timestamp) return '';

    const now = Date.now();
    const then = new Date(timestamp).getTime();
    const diff = Math.floor((now - then) / 1000);

    if (diff < 60) return '刚刚';
    if (diff < 3600) return `${Math.floor(diff / 60)}分钟前`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}小时前`;
    return `${Math.floor(diff / 86400)}天前`;
}

/**
 * Check if session process is still running
 */
function isProcessRunning(pid) {
    try {
        // On macOS, we can check via kill
        process.kill(pid, 0);
        return true;
    } catch (e) {
        return false;
    }
}

/**
 * Get context window size from settings or default
 */
function getContextWindowSize() {
    const settingsPath = path.join(CLAUDE_DIR, 'settings.json');
    try {
        if (fs.existsSync(settingsPath)) {
            const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
            // Default model context window
            return 200000;
        }
    } catch (e) {
        // Use default
    }
    return 200000;
}

/**
 * Calculate context usage percentage
 */
function calculateContextUsage(inputTokens, cacheRead, cacheCreate, maxContext) {
    // Approximate context usage based on input tokens
    const total = inputTokens + cacheRead + cacheCreate;
    return Math.round((total / maxContext) * 100);
}

/**
 * Main data collection function
 */
function collectData() {
    const sessions = getSessions();
    const maxContext = getContextWindowSize();
    const activeSessions = [];

    for (const session of sessions) {
        // Check if process is running
        if (!isProcessRunning(session.pid)) {
            continue; // Skip inactive sessions
        }

        const transcriptPath = getTranscriptPath(session);
        const transcriptStats = parseTranscript(transcriptPath);

        // Calculate duration
        const startedAt = session.startedAt || Date.now();
        const duration = Date.now() - startedAt;

        // Determine status (simplified - would need more info for real status)
        let status = 'idle';
        if (transcriptStats.recentMessages.length > 0) {
            const lastMsg = transcriptStats.recentMessages[transcriptStats.recentMessages.length - 1];
            if (lastMsg.type === 'user' && Date.now() - startedAt < 60000) {
                status = 'running';
            }
        }

        const contextUsed = Math.round((transcriptStats.totalInputTokens + transcriptStats.totalCacheRead + transcriptStats.totalCacheCreate) / 1000);

        activeSessions.push({
            id: session.sessionId.split('-')[0] + '-' + session.sessionId.split('-')[1], // Short ID
            fullId: session.sessionId,
            pid: session.pid,
            status: status,
            startTime: startedAt,
            workDir: session.cwd || '/unknown',
            model: session.model || 'claude-sonnet-4-6',
            contextUsed: contextUsed,
            contextTotal: maxContext / 1000,
            tokensInput: transcriptStats.totalInputTokens,
            tokensOutput: transcriptStats.totalOutputTokens,
            cacheRead: transcriptStats.totalCacheRead,
            cacheCreate: transcriptStats.totalCacheCreate,
            recentMessages: transcriptStats.recentMessages
        });
    }

    return {
        timestamp: new Date().toISOString(),
        sessions: activeSessions
    };
}

// If run directly, output JSON
if (require.main === module) {
    const data = collectData();
    console.log(JSON.stringify(data, null, 2));
}

module.exports = { collectData, getSessions, parseTranscript };
