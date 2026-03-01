#!/bin/bash
# ============================================================================
# 自动网络性能检测与内核优化脚本
# 适配：Debian/Ubuntu, CentOS/RHEL/Alma/Rocky, Alpine, Arch, Fedora
# 作者：kejilion
# ============================================================================

# ======================== 颜色定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ======================== 工具函数 ========================
info()  { echo -e "${CYAN}[检测]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
fail()  { echo -e "${RED}[✗]${NC} $*"; }
title() { echo -e "\n${WHITE}━━━ $* ━━━${NC}"; }

# 获取内核主版本号用于兼容性判断
kernel_version() {
    local ver
    ver=$(uname -r | grep -oP '^\d+\.\d+')
    echo "$ver"
}

# 比较版本号: version_ge 5.4 4.9 => true
version_ge() {
    printf '%s\n%s' "$2" "$1" | sort -V -C
}

# 安全读取 sysctl 值
sysctl_get() {
    sysctl -n "$1" 2>/dev/null || echo "N/A"
}

# 获取发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint|pop|kali) echo "debian" ;;
            centos|rhel|almalinux|rocky|ol|amzn|fedora) echo "rhel" ;;
            alpine) echo "alpine" ;;
            arch|manjaro|endeavouros) echo "arch" ;;
            opensuse*|sles) echo "suse" ;;
            *) echo "unknown" ;;
        esac
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# ======================== 网络检测 ========================

# 检测网卡速率（Mbps）
detect_link_speed() {
    local speed=0
    local iface

    # 获取默认路由网卡
    iface=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
    [ -z "$iface" ] && iface=$(ls /sys/class/net/ | grep -v lo | head -1)

    if [ -n "$iface" ]; then
        # 尝试 ethtool
        if command -v ethtool &>/dev/null; then
            speed=$(ethtool "$iface" 2>/dev/null | awk '/Speed:/{gsub(/[^0-9]/,"",$2); print $2}')
        fi

        # 尝试 sysfs
        if [ -z "$speed" ] || [ "$speed" = "0" ]; then
            speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null)
        fi
    fi

    # VPS 虚拟网卡可能读不到速率，默认 1000
    [ -z "$speed" ] || [ "$speed" -le 0 ] 2>/dev/null && speed=1000

    echo "$speed"
}

# 检测网络延迟（ms，ping 多个公共 DNS）
detect_latency() {
    local total=0 count=0 avg
    local targets=("8.8.8.8" "1.1.1.1" "9.9.9.9" "208.67.222.222")

    for t in "${targets[@]}"; do
        local rtt
        rtt=$(ping -c 3 -W 2 "$t" 2>/dev/null | awk -F'/' '/avg/{print $5}')
        if [ -n "$rtt" ]; then
            total=$(awk "BEGIN{print $total + $rtt}")
            count=$((count + 1))
        fi
    done

    if [ "$count" -gt 0 ]; then
        avg=$(awk "BEGIN{printf \"%.1f\", $total / $count}")
    else
        avg="50"
    fi

    echo "$avg"
}

# 检测丢包率（%）
detect_packet_loss() {
    local loss
    loss=$(ping -c 10 -W 2 8.8.8.8 2>/dev/null | awk -F',' '/loss/{gsub(/%/,"",$3); gsub(/ packet/,"",$3); print $3+0}')
    [ -z "$loss" ] && loss=0
    echo "$loss"
}

# 获取当前 TCP 拥塞算法
detect_congestion() {
    sysctl_get net.ipv4.tcp_congestion_control
}

# 检测总物理内存（MB）
detect_memory_mb() {
    awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo
}

# ======================== 带宽分级 ========================
# 返回: low / medium / high / ultra
classify_bandwidth() {
    local speed=$1
    if [ "$speed" -lt 100 ]; then
        echo "low"
    elif [ "$speed" -lt 1000 ]; then
        echo "medium"
    elif [ "$speed" -lt 10000 ]; then
        echo "high"
    else
        echo "ultra"
    fi
}

# ======================== 核心优化函数 ========================

auto_optimize_network() {
    local CONF="/etc/sysctl.d/99-network-optimize.conf"
    local BACKUP="/etc/sysctl.d/99-network-optimize.conf.bak.$(date +%s)"
    local KVER
    KVER=$(kernel_version)
    local DISTRO
    DISTRO=$(detect_distro)

    echo -e "${WHITE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          自动网络性能检测与内核优化                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # ── 权限检查 ──
    if [ "$(id -u)" -ne 0 ]; then
        fail "请以 root 权限运行"
        return 1
    fi

    # ── 环境信息 ──
    title "环境信息"
    info "发行版: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "$DISTRO")"
    info "内核版本: $(uname -r)"
    info "架构: $(uname -m)"
    info "内存: $(detect_memory_mb) MB"

    # ── 网络检测 ──
    title "网络性能检测"

    local SPEED LATENCY LOSS CONGESTION MEM_MB BW_CLASS

    info "检测网卡速率..."
    SPEED=$(detect_link_speed)
    ok "链路速率: ${SPEED} Mbps"

    info "检测网络延迟..."
    LATENCY=$(detect_latency)
    ok "平均延迟: ${LATENCY} ms"

    info "检测丢包率..."
    LOSS=$(detect_packet_loss)
    ok "丢包率: ${LOSS}%"

    CONGESTION=$(detect_congestion)
    ok "当前拥塞算法: ${CONGESTION}"

    MEM_MB=$(detect_memory_mb)
    BW_CLASS=$(classify_bandwidth "$SPEED")

    title "检测结论"
    case "$BW_CLASS" in
        low)   info "带宽等级: ${YELLOW}低带宽 (<100M)${NC} → 保守优化" ;;
        medium) info "带宽等级: ${CYAN}中带宽 (100M-1G)${NC} → 标准优化" ;;
        high)  info "带宽等级: ${GREEN}高带宽 (1G-10G)${NC} → 激进优化" ;;
        ultra) info "带宽等级: ${WHITE}超高带宽 (>10G)${NC} → 极致优化" ;;
    esac

    local HIGH_LATENCY=false
    if [ "$(awk "BEGIN{print ($LATENCY > 100)}")" = "1" ]; then
        HIGH_LATENCY=true
        warn "高延迟网络 (${LATENCY}ms > 100ms)，启用额外优化"
    fi

    # ── 备份现有配置 ──
    title "备份与准备"
    if [ -f "$CONF" ]; then
        cp "$CONF" "$BACKUP"
        ok "已备份: $BACKUP"
    else
        ok "首次优化，无需备份"
    fi

    # ── 根据带宽等级设定参数 ──
    local TCP_RMEM_MAX TCP_WMEM_MAX TCP_RMEM TCP_WMEM
    local NETDEV_BUDGET NETDEV_BUDGET_USECS
    local SOMAXCONN NETDEV_BACKLOG
    local CONNTRACK_MAX

    case "$BW_CLASS" in
        low)
            TCP_RMEM="4096 65536 2097152"
            TCP_WMEM="4096 65536 2097152"
            TCP_RMEM_MAX=2097152
            TCP_WMEM_MAX=2097152
            SOMAXCONN=1024
            NETDEV_BACKLOG=1000
            NETDEV_BUDGET=300
            NETDEV_BUDGET_USECS=2000
            CONNTRACK_MAX=65536
            ;;
        medium)
            TCP_RMEM="4096 131072 16777216"
            TCP_WMEM="4096 131072 16777216"
            TCP_RMEM_MAX=16777216
            TCP_WMEM_MAX=16777216
            SOMAXCONN=4096
            NETDEV_BACKLOG=5000
            NETDEV_BUDGET=600
            NETDEV_BUDGET_USECS=4000
            CONNTRACK_MAX=262144
            ;;
        high)
            TCP_RMEM="4096 262144 67108864"
            TCP_WMEM="4096 262144 67108864"
            TCP_RMEM_MAX=67108864
            TCP_WMEM_MAX=67108864
            SOMAXCONN=8192
            NETDEV_BACKLOG=10000
            NETDEV_BUDGET=1200
            NETDEV_BUDGET_USECS=6000
            CONNTRACK_MAX=524288
            ;;
        ultra)
            TCP_RMEM="4096 524288 134217728"
            TCP_WMEM="4096 524288 134217728"
            TCP_RMEM_MAX=134217728
            TCP_WMEM_MAX=134217728
            SOMAXCONN=16384
            NETDEV_BACKLOG=20000
            NETDEV_BUDGET=2400
            NETDEV_BUDGET_USECS=8000
            CONNTRACK_MAX=1048576
            ;;
    esac

    # 高延迟追加：加大初始窗口
    local HIGH_LAT_EXTRA=""
    if $HIGH_LATENCY; then
        # 高延迟网络使用更大的初始拥塞窗口提升吞吐
        HIGH_LAT_EXTRA="
# ── 高延迟网络额外优化 ──
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384"
    fi

    # 内存不足时缩小缓冲区
    if [ "$MEM_MB" -lt 512 ]; then
        warn "内存不足 512MB，缩小 TCP 缓冲区"
        TCP_RMEM="4096 32768 1048576"
        TCP_WMEM="4096 32768 1048576"
        TCP_RMEM_MAX=1048576
        TCP_WMEM_MAX=1048576
        CONNTRACK_MAX=32768
    fi

    # ── BBR 检测与加载 ──
    title "TCP 拥塞算法优化"
    local USE_BBR=false
    local TARGET_CC="cubic"

    if version_ge "$KVER" "4.9"; then
        # 内核 >= 4.9 支持 BBR
        if ! lsmod 2>/dev/null | grep -q tcp_bbr; then
            modprobe tcp_bbr 2>/dev/null
            if lsmod 2>/dev/null | grep -q tcp_bbr; then
                ok "BBR 模块已加载"
            else
                warn "BBR 模块加载失败，使用 cubic"
            fi
        fi

        if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
            USE_BBR=true
            TARGET_CC="bbr"
            ok "拥塞算法: cubic → ${GREEN}BBR${NC}"
        fi
    else
        warn "内核 $KVER < 4.9，不支持 BBR，保持 cubic"
    fi

    # BBR 配合 fq 队列调度
    local QDISC="fq"
    if ! $USE_BBR; then
        QDISC="fq_codel"
    fi

    # ── 生成优化配置 ──
    title "写入优化配置"

    cat > "$CONF" << SYSCTL
# ============================================================================
# 自动网络优化配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 带宽等级: $BW_CLASS (${SPEED}Mbps)
# 平均延迟: ${LATENCY}ms | 丢包率: ${LOSS}%
# 内核: $(uname -r) | 发行版: $DISTRO | 内存: ${MEM_MB}MB
# ============================================================================

# ── TCP 拥塞控制 ──
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $TARGET_CC

# ── TCP 缓冲区 ──
net.core.rmem_max = $TCP_RMEM_MAX
net.core.wmem_max = $TCP_WMEM_MAX
net.core.rmem_default = $(echo "$TCP_RMEM" | awk '{print $2}')
net.core.wmem_default = $(echo "$TCP_WMEM" | awk '{print $2}')
net.ipv4.tcp_rmem = $TCP_RMEM
net.ipv4.tcp_wmem = $TCP_WMEM
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# ── 连接队列 ──
net.core.somaxconn = $SOMAXCONN
net.core.netdev_max_backlog = $NETDEV_BACKLOG
net.core.netdev_budget = $NETDEV_BUDGET
$(sysctl -n net.core.netdev_budget_usecs &>/dev/null && echo "net.core.netdev_budget_usecs = $NETDEV_BUDGET_USECS" || echo "# netdev_budget_usecs 不支持，跳过")

# ── TCP 连接优化 ──
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_max_syn_backlog = $SOMAXCONN
net.ipv4.tcp_max_tw_buckets = 65536
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1

# ── 内存与端口 ──
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_mem = $((MEM_MB * 1024 / 8)) $((MEM_MB * 1024 / 4)) $((MEM_MB * 1024 / 2))
net.ipv4.tcp_max_orphans = 32768

# ── 安全与防护 ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# ── IPv6 优化 ──
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ── 文件描述符 ──
fs.file-max = 1048576
fs.nr_open = 1048576

# ── 连接跟踪 ──
$(if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
    echo "net.netfilter.nf_conntrack_max = $CONNTRACK_MAX"
    echo "net.netfilter.nf_conntrack_tcp_timeout_established = 7200"
    echo "net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30"
    echo "net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15"
    echo "net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 15"
else
    echo "# conntrack 未启用，跳过"
fi)
$HIGH_LAT_EXTRA
SYSCTL

    ok "配置已写入: $CONF"

    # ── 应用配置 ──
    title "应用优化"
    local apply_errors
    apply_errors=$(sysctl -p "$CONF" 2>&1 | grep -i "error\|invalid\|cannot" || true)

    if [ -n "$apply_errors" ]; then
        warn "部分参数不支持（已跳过）:"
        echo "$apply_errors" | while read -r line; do
            echo -e "  ${YELLOW}$line${NC}"
        done
    fi
    ok "sysctl 参数已应用"

    # ── 设置文件描述符限制 ──
    if ! grep -q "# network-optimize" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITS'

# network-optimize - 自动网络优化添加
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS
        ok "文件描述符限制已更新"
    fi

    # ── 持久化 BBR 模块 ──
    if $USE_BBR; then
        if [ ! -f /etc/modules-load.d/bbr.conf ]; then
            echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null
            ok "BBR 模块持久化"
        fi
    fi

    # ── 优化摘要 ──
    title "优化摘要"
    echo -e "${WHITE}┌──────────────────────────────────────────────────┐${NC}"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "项目" "值"
    echo -e "${WHITE}├──────────────────────────────────────────────────┤${NC}"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "带宽等级" "$BW_CLASS (${SPEED}Mbps)"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "拥塞算法" "$TARGET_CC"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "队列调度" "$QDISC"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "TCP 缓冲区(max)" "$(numfmt --to=iec $TCP_RMEM_MAX 2>/dev/null || echo ${TCP_RMEM_MAX})"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "连接队列" "$SOMAXCONN"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "网络延迟" "${LATENCY}ms"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "高延迟优化" "$(if $HIGH_LATENCY; then echo '已启用'; else echo '未需要'; fi)"
    printf "${WHITE}│${NC} %-20s ${WHITE}│${NC} %-25s ${WHITE}│${NC}\n" "配置文件" "$CONF"
    echo -e "${WHITE}└──────────────────────────────────────────────────┘${NC}"

    echo -e "\n${GREEN}网络优化完成！${NC}"
    echo -e "回滚命令: ${CYAN}restore_network_defaults${NC}"
}

# ======================== 回滚函数 ========================

restore_network_defaults() {
    local CONF="/etc/sysctl.d/99-network-optimize.conf"

    title "回滚网络优化"

    if [ "$(id -u)" -ne 0 ]; then
        fail "请以 root 权限运行"
        return 1
    fi

    # 查找最近的备份
    local latest_bak
    latest_bak=$(ls -t /etc/sysctl.d/99-network-optimize.conf.bak.* 2>/dev/null | head -1)

    if [ -n "$latest_bak" ]; then
        cp "$latest_bak" "$CONF"
        sysctl -p "$CONF" 2>/dev/null
        ok "已从备份恢复: $latest_bak"
    elif [ -f "$CONF" ]; then
        rm -f "$CONF"
        sysctl --system 2>/dev/null
        ok "已删除优化配置，恢复系统默认"
    else
        warn "没有优化配置需要回滚"
        return 0
    fi

    # 清理 limits.conf 添加的部分
    if grep -q "# network-optimize" /etc/security/limits.conf 2>/dev/null; then
        sed -i '/# network-optimize/,+4d' /etc/security/limits.conf
        ok "文件描述符限制已恢复"
    fi

    # 清理 BBR 持久化
    rm -f /etc/modules-load.d/bbr.conf 2>/dev/null

    ok "网络配置已回滚"
}

# ======================== 查看当前状态 ========================

show_network_status() {
    title "当前网络内核参数"

    local params=(
        "net.ipv4.tcp_congestion_control"
        "net.core.default_qdisc"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.core.somaxconn"
        "net.core.netdev_max_backlog"
        "net.ipv4.tcp_fastopen"
        "net.ipv4.tcp_tw_reuse"
        "net.ipv4.tcp_fin_timeout"
        "net.ipv4.ip_local_port_range"
        "net.ipv4.tcp_mtu_probing"
        "fs.file-max"
    )

    for p in "${params[@]}"; do
        local val
        val=$(sysctl_get "$p")
        printf "  %-45s = %s\n" "$p" "$val"
    done

    if [ -f /etc/sysctl.d/99-network-optimize.conf ]; then
        echo ""
        ok "优化配置已安装: /etc/sysctl.d/99-network-optimize.conf"
    else
        echo ""
        warn "未检测到优化配置"
    fi
}

# ======================== 入口 ========================
# 用法:
#   source network-optimize.sh
#   auto_optimize_network    # 自动检测并优化
#   show_network_status      # 查看当前状态
#   restore_network_defaults # 回滚到默认
#
# 或直接运行:
#   bash network-optimize.sh
# ========================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    auto_optimize_network
fi
