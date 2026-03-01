#!/bin/bash
# 内核调优模块测试脚本
# 模拟 kejilion.sh 的颜色变量和依赖函数，测试所有模式

# 模拟颜色变量
gl_lv='\033[0;32m'
gl_bai='\033[0m'
gl_huang='\033[1;33m'

# 模拟依赖函数
root_use() { true; }
send_stats() { true; }
break_end() { true; }
gh_proxy=""

# 加载模块
source kernel-optimize-module.sh

PASS=0
FAIL=0

test_case() {
    local name="$1"
    local result="$2"
    if [ "$result" -eq 0 ]; then
        echo "✅ $name"
        PASS=$((PASS + 1))
    else
        echo "❌ $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== 环境信息 ==="
cat /etc/os-release 2>/dev/null | grep PRETTY_NAME || true
echo "Kernel: $(uname -r)"
echo "Memory: $(_get_mem_mb)MB"
echo ""

# ── 测试 _get_mem_mb ──
MEM=$(_get_mem_mb)
[ -n "$MEM" ] && [ "$MEM" -gt 0 ] 2>/dev/null
test_case "_get_mem_mb (${MEM}MB)" $?

# ── 测试各场景配置生成 ──
CONF="/etc/sysctl.d/99-kejilion-optimize.conf"
mkdir -p /etc/sysctl.d /etc/security

for scene in high balanced web stream game; do
    rm -f "$CONF"
    _kernel_optimize_core "测试-${scene}" "$scene" >/dev/null 2>&1
    
    # 验证配置文件生成
    [ -f "$CONF" ]
    test_case "config generated ($scene)" $?
    
    # 验证关键参数存在
    grep -q "tcp_congestion_control" "$CONF" 2>/dev/null
    test_case "has tcp_congestion_control ($scene)" $?
    
    grep -q "vm.swappiness" "$CONF" 2>/dev/null
    test_case "has vm.swappiness ($scene)" $?
    
    grep -q "fs.file-max" "$CONF" 2>/dev/null
    test_case "has fs.file-max ($scene)" $?
    
    grep -q "tcp_fastopen" "$CONF" 2>/dev/null
    test_case "has tcp_fastopen ($scene)" $?
    
    grep -q "tcp_mem" "$CONF" 2>/dev/null
    test_case "has tcp_mem ($scene)" $?
done

# ── 测试直播模式有 UDP 额外参数 ──
rm -f "$CONF"
_kernel_optimize_core "测试-stream" "stream" >/dev/null 2>&1
grep -q "udp_rmem_min" "$CONF" 2>/dev/null
test_case "stream mode has udp_rmem_min" $?

# ── 测试游戏模式有低延迟参数 ──
rm -f "$CONF"
_kernel_optimize_core "测试-game" "game" >/dev/null 2>&1
grep -q "tcp_slow_start_after_idle" "$CONF" 2>/dev/null
test_case "game mode has tcp_slow_start_after_idle" $?

# ── 测试还原函数 ──
restore_defaults >/dev/null 2>&1
[ ! -f "$CONF" ]
test_case "restore_defaults removes config" $?

# ── 测试接口兼容性 ──
tiaoyou_moshi="测试高性能"
optimize_high_performance >/dev/null 2>&1
[ -f "$CONF" ]
test_case "optimize_high_performance interface" $?
rm -f "$CONF"

optimize_balanced >/dev/null 2>&1
[ -f "$CONF" ]
test_case "optimize_balanced interface" $?
rm -f "$CONF"

optimize_web_server >/dev/null 2>&1
[ -f "$CONF" ]
test_case "optimize_web_server interface" $?

# ── 清理 ──
restore_defaults >/dev/null 2>&1

echo ""
echo "=== 结果: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
