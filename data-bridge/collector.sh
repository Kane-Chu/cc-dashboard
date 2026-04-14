#!/bin/bash

# Claude Code CLI 数据收集脚本
# 用于收集本地 Claude Code 进程信息，可与 Dashboard 集成

OUTPUT_FILE="/tmp/claude-sessions.json"

# 获取 Claude Code 进程列表
get_claude_processes() {
    # 查找包含 claude 的进程（排除 grep 本身）
    ps aux | grep -i "claude" | grep -v grep | grep -v "claude-dashboard"
}

# 获取进程详细信息
get_process_info() {
    local pid=$1
    local info={}

    # 基础信息
    local cmd=$(ps -p $pid -o command= 2>/dev/null)
    local etime=$(ps -p $pid -o etime= 2>/dev/null)
    local cpu=$(ps -p $pid -o %cpu= 2>/dev/null)
    local mem=$(ps -p $pid -o %mem= 2>/dev/null)

    # 工作目录
    local cwd=$(lsof -p $pid 2>/dev/null | grep cwd | awk '{print $9}')
    if [ -z "$cwd" ]; then
        cwd=$(pwdx $pid 2>/dev/null | cut -d: -f2 | tr -d ' ')
    fi

    # 从命令行提取模型信息
    local model=$(echo "$cmd" | grep -oE "claude-[a-z0-9-]+" | head -1)
    if [ -z "$model" ]; then
        model="claude-sonnet-4-6"  # 默认值
    fi

    echo "{"
    echo "  \"pid\": $pid,"
    echo "  \"command\": \"$cmd\","
    echo "  \"etime\": \"$etime\","
    echo "  \"cpu\": \"$cpu\","
    echo "  \"mem\": \"$mem\","
    echo "  \"cwd\": \"$cwd\","
    echo "  \"model\": \"$model\""
    echo "}"
}

# 生成 JSON 输出
generate_json() {
    echo "{"
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"sessions\": ["

    local first=true
    ps aux | grep -i "claude" | grep -v grep | grep -v "claude-dashboard" | while read line; do
        pid=$(echo "$line" | awk '{print $2}')

        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi

        get_process_info $pid
    done

    echo ""
    echo "  ]"
    echo "}"
}

# 主函数
main() {
    echo "正在收集 Claude Code CLI 进程信息..."

    # 检查是否有 Claude 进程在运行
    if ! get_claude_processes > /dev/null 2>&1; then
        echo "未找到正在运行的 Claude Code 进程"
        echo '{"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","sessions":[]}' > "$OUTPUT_FILE"
        exit 0
    fi

    # 生成 JSON 并保存
    generate_json > "$OUTPUT_FILE"

    echo "数据已保存到: $OUTPUT_FILE"
    echo "Session 数量: $(cat "$OUTPUT_FILE" | grep -c '"pid"')"
}

# 持续监控模式
watch_mode() {
    echo "启动监控模式 (每 5 秒更新)..."
    while true; do
        main
        sleep 5
    done
}

# 解析参数
case "${1:-}" in
    --watch|-w)
        watch_mode
        ;;
    --help|-h)
        echo "Claude Code CLI 数据收集器"
        echo ""
        echo "用法:"
        echo "  $0              一次性收集数据"
        echo "  $0 --watch      持续监控模式"
        echo "  $0 --help       显示帮助"
        echo ""
        echo "输出: $OUTPUT_FILE"
        ;;
    *)
        main
        ;;
esac
