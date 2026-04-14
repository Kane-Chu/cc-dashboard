# Claude Code CLI Dashboard

一个具有科技感的实时监控面板，用于可视化展示本地 Claude Code CLI 的使用情况。

## 功能特性

- **Session 监控**: 展示所有打开的 Claude Code sessions
- **实时状态**: 显示每个 session 的当前状态（执行中/等待确认/空闲）
- **执行时长**: 实时更新的运行时间计时器
- **Context 占用**: 可视化进度条展示 context 使用情况
- **Token 统计**: 显示 Input/Output/总计 Token 消耗
- **工作目录**: 显示每个 session 的工作路径
- **模型信息**: 显示使用的 Claude 模型版本
- **最近交互**: 展示最近 5 条交互消息，等待确认的消息会高亮显示

## 设计风格

- 深色科技主题
- 霓虹蓝/紫色渐变配色
- 毛玻璃效果卡片
- 动态粒子背景
- 扫描线效果
- 状态指示灯动画
- 实时数据更新

## 使用方法

### 方式一：直接打开
```bash
open index.html
```

### 方式二：使用本地服务器
```bash
# Python 3
python -m http.server 8080

# Node.js
npx serve .

# 然后访问 http://localhost:8080
```

## 数据集成（可选）

目前页面使用模拟数据展示。要接入真实数据，可以：

1. 创建一个数据收集脚本，读取 Claude Code CLI 的进程信息
2. 通过 WebSocket 或轮询 API 将数据发送到前端
3. 修改 `generateMockSessions()` 函数为真实数据获取

### 数据收集思路

```bash
# 查找 Claude Code 进程
ps aux | grep claude

# 获取进程详细信息（内存、CPU 等）
ps -p <PID> -o pid,etime,command

# 获取工作目录
lsof -p <PID> | grep cwd
```

## 技术栈

- React 18
- Tailwind CSS
- 原生 JavaScript (Babel 转译)
- Lucide Icons

## 文件结构

```
cc-dashboard/
├── index.html      # 主页面（包含所有代码）
├── README.md       # 说明文档
└── data-bridge/    # 数据桥接脚本（可选扩展）
    └── collector.sh
```

## 预览

页面包含：
- 顶部统计概览卡片
- Session 详细信息卡片网格
- 每个 session 显示：ID、PID、状态、时长、工作目录、模型、Context 使用、Token 统计、最近交互
