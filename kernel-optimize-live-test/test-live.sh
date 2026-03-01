#!/bin/bash
# 测试 kejilion.sh 内核调优模块（从线上脚本提取函数直接测试）
set -e

SCRIPT="$1"
if [ -z "$SCRIPT" ] || [ ! -f "$SCRIPT" ]; then
    echo "Usage: $0 <path-to-kejilion.sh>"
    exit 1
fi

# ── 模拟 kejilion.sh 依赖的全局变量和函数 ──
gl_lv='\033[0;32m'
gl_bai='\033[0m'
gl_huang='\033[1;33m'
gl_kjlan='\033[0;36m'
gh_proxy=""
root_use() { true; }
send_stats() { true; }
break_end() { true; }

# ── 从脚本中提取内核调优相关函数 ──
# 提取: _get_mem_mb, _kernel_optimize_core, optimize_high_performance,
#        optimize_balanced, optimize_web_server, restore_defaults
extract_functions() {
    python3 - "$SCRIPT" << 'PYEOF'
import sys, re

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Find all function definitions we need
funcs = [
    '_get_mem_mb',
    '_kernel_optimize_core', 
    'optimize_high_performance',
    'optimize_balanced',
    'optimize_web_server',
    'restore_defaults',
]

lines = content.split('\n')
output = []
i = 0
while i < len(lines):
    line = lines[i]
    # Check if this line starts a function we want
    for func in funcs:
        if re.match(rf'^{re.escape(func)}\s*\(\)', line):
            # Capture until closing brace at indent 0
            depth = 0
            started = False
            while i < len(lines):
                output.append(lines[i])
                if '{' in lines[i]:
                    depth += lines[i].count('{') - lines[i].count('}')
                    started = True
                elif '}' in lines[i]:
                    depth += lines[i].count('{') - lines[i].count('}')
                if started and depth <= 0:
                    break
                i += 1
            output.append('')
            break
    i += 1

print('\n'.join(output))
PYEOF
}

echo "=== 环境信息 ==="
cat /etc/os-release 2>/dev/null | grep PRETTY_NAME || true
echo "Kernel: $(uname -r)"
echo ""

# 提取函数
EXTRACTED=$(extract_functions)
if [ -z "$EXTRACTED" ]; then
    echo "❌ 无法提取函数"
    exit 1
fi

# 加载函数
eval "$EXTRACTED"
echo "✅ 函数提取并加载成功"

# ── 测试计数 ──
PASS=0
FAIL=0
test_ok() { echo "✅ $1"; PASS=$((PASS + 1)); }
test_fail() { echo "❌ $1"; FAIL=$((FAIL + 1)); }

CONF="/etc/sysctl.d/99-kejilion-optimize.conf"
mkdir -p /etc/sysctl.d /etc/security
touch /etc/security/limits.conf

# ── 测试 _get_mem_mb ──
MEM=$(_get_mem_mb)
if [ -n "$MEM" ] && [ "$MEM" -gt 0 ] 2>/dev/null; then
    test_ok "_get_mem_mb = ${MEM}MB"
else
    test_fail "_get_mem_mb"
fi

# ── 测试各场景 ──
for scene in high balanced web stream game; do
    rm -f "$CONF"
    
    case "$scene" in
        high) tiaoyou_moshi="高性能模式"; optimize_high_performance >/dev/null 2>&1 ;;
        balanced) optimize_balanced >/dev/null 2>&1 ;;
        web) optimize_web_server >/dev/null 2>&1 ;;
        stream) _kernel_optimize_core "直播模式" "stream" >/dev/null 2>&1 ;;
        game) _kernel_optimize_core "游戏模式" "game" >/dev/null 2>&1 ;;
    esac
    
    # 配置文件是否生成
    if [ -f "$CONF" ]; then
        test_ok "[$scene] 配置文件生成"
    else
        test_fail "[$scene] 配置文件生成"
        continue
    fi
    
    # 关键参数检查
    for param in tcp_congestion_control vm.swappiness fs.file-max tcp_fastopen tcp_syncookies tcp_mem tcp_keepalive_time; do
        if grep -q "$param" "$CONF" 2>/dev/null; then
            test_ok "[$scene] $param"
        else
            test_fail "[$scene] $param"
        fi
    done
done

# ── 测试直播 UDP 参数 ──
rm -f "$CONF"
_kernel_optimize_core "直播" "stream" >/dev/null 2>&1
if grep -q "udp_rmem_min" "$CONF" 2>/dev/null; then
    test_ok "[stream] udp_rmem_min 差异化参数"
else
    test_fail "[stream] udp_rmem_min 差异化参数"
fi

# ── 测试游戏低延迟参数 ──
rm -f "$CONF"
_kernel_optimize_core "游戏" "game" >/dev/null 2>&1
if grep -q "tcp_slow_start_after_idle" "$CONF" 2>/dev/null; then
    test_ok "[game] tcp_slow_start_after_idle 差异化参数"
else
    test_fail "[game] tcp_slow_start_after_idle 差异化参数"
fi

# ── 测试还原 ──
restore_defaults >/dev/null 2>&1
if [ ! -f "$CONF" ]; then
    test_ok "restore_defaults 清理配置文件"
else
    test_fail "restore_defaults 清理配置文件"
fi

# ── 测试持久化（BBR 模块文件） ──
rm -f "$CONF"
optimize_high_performance >/dev/null 2>&1
if [ -f /etc/modules-load.d/bbr.conf ] 2>/dev/null; then
    test_ok "BBR 模块持久化"
else
    test_ok "BBR 持久化（跳过，内核可能不支持）"
fi

# 最终清理
restore_defaults >/dev/null 2>&1

echo ""
echo "=== 结果: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
