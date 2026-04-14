# CLAUDE.md - Claude Code CLI Dashboard

## 项目简介

Claude Code CLI 的实时监控 Dashboard，提供科技感的可视化界面展示本地会话状态。

## 技术栈

- **前端**: HTML + Tailwind CSS + 原生 JavaScript
- **样式**: 深色科技主题，霓虹蓝/紫渐变，毛玻璃效果
- **数据**: 目前使用模拟数据，预留了 `/api/sessions` 接口

## 文件结构

```
cc-dashboard/
├── index.html      # 主页面（单文件应用）
├── server.js       # Node.js 服务器（提供 API）
├── README.md       # 项目说明
└── data-bridge/    # 数据收集脚本
```

## 关键代码位置

### 样式变量
- 文件: `index.html:12-19`
- CSS 变量定义主题色（霓虹青、紫、粉）

### Session 卡片尺寸
- 紧凑视图: `index.html:234-248`
  - padding: `10px 12px`
  - 网格: `grid-cols-1 md:grid-cols-2 xl:grid-cols-4`
- 浮动展开视图: `index.html:251-265`
  - width: `90%`, max-width: `500px` (需更新)
  - 当前实际值: `index.html:590`
    - width: `94%`, max-width: `700px`, max-height: `85vh`

### 数据模拟
- Mock 数据: `index.html:407-484`
- 获取函数: `index.html:487-489`
- API 端点: `index.html:388-404`

### 渲染函数
- 主渲染: `index.html:750-798`
- Session 卡片: `index.html:536-578`
- 浮动卡片: `index.html:589-667`
- 统计卡片: `index.html:719-747`

## 修改建议

### 调整卡片大小
如果需要修改浮动卡片尺寸，编辑第 590 行：
```javascript
// 当前
width:94%;max-width:700px;max-height:85vh

// 改为更小
width:90%;max-width:500px;max-height:80vh
```

### 添加新状态类型
1. 在 `getStatusConfig` 函数 (line 512-519) 添加状态配置
2. 在 CSS 中添加对应的状态点样式 (line 128-142)

### 接入真实数据
1. 修改 `fetchRealData()` 函数
2. 确保服务器提供 `/api/sessions` 端点
3. 设置 `useMock = false`

## 开发命令

```bash
# 启动本地服务器
node server.js

# 或直接用 Python
python -m http.server 8080
```

## 注意事项

- 单文件应用，所有代码在 `index.html` 中
- 使用 Tailwind CDN，无需构建步骤
- 响应式设计，支持移动端
