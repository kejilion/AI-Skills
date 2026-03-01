# ============================================================================
# Linux 内核调优模块（重构版）
# 统一核心函数 + 场景差异化参数 + 持久化到配置文件 + 硬件自适应
# 替换原 optimize_high_performance / optimize_balanced / optimize_web_server / restore_defaults
# ============================================================================

# 获取内存大小（MB）
_get_mem_mb() {
	awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo
}

# 统一内核调优核心函数
# 参数: $1 = 模式名称, $2 = 场景 (high/balanced/web/stream/game)
_kernel_optimize_core() {
	local mode_name="$1"
	local scene="${2:-high}"
	local CONF="/etc/sysctl.d/99-kejilion-optimize.conf"
	local MEM_MB=$(_get_mem_mb)

	echo -e "${gl_lv}切换到${mode_name}...${gl_bai}"

	# ── 根据场景设定参数 ──
	local SWAPPINESS DIRTY_RATIO DIRTY_BG_RATIO OVERCOMMIT MIN_FREE_KB VFS_PRESSURE
	local RMEM_MAX WMEM_MAX TCP_RMEM TCP_WMEM
	local SOMAXCONN BACKLOG SYN_BACKLOG
	local PORT_RANGE SCHED_AUTOGROUP THP NUMA FIN_TIMEOUT
	local KEEPALIVE_TIME KEEPALIVE_INTVL KEEPALIVE_PROBES

	case "$scene" in
		high|stream|game)
			# 高性能/直播/游戏：激进参数
			SWAPPINESS=10
			DIRTY_RATIO=15
			DIRTY_BG_RATIO=5
			OVERCOMMIT=1
			VFS_PRESSURE=50
			RMEM_MAX=67108864
			WMEM_MAX=67108864
			TCP_RMEM="4096 262144 67108864"
			TCP_WMEM="4096 262144 67108864"
			SOMAXCONN=8192
			BACKLOG=250000
			SYN_BACKLOG=8192
			PORT_RANGE="1024 65535"
			SCHED_AUTOGROUP=0
			THP="never"
			NUMA=0
			FIN_TIMEOUT=10
			KEEPALIVE_TIME=300
			KEEPALIVE_INTVL=30
			KEEPALIVE_PROBES=5
			;;
		web)
			# 网站服务器：高并发优先
			SWAPPINESS=10
			DIRTY_RATIO=20
			DIRTY_BG_RATIO=10
			OVERCOMMIT=1
			VFS_PRESSURE=50
			RMEM_MAX=33554432
			WMEM_MAX=33554432
			TCP_RMEM="4096 131072 33554432"
			TCP_WMEM="4096 131072 33554432"
			SOMAXCONN=16384
			BACKLOG=10000
			SYN_BACKLOG=16384
			PORT_RANGE="1024 65535"
			SCHED_AUTOGROUP=0
			THP="never"
			NUMA=0
			FIN_TIMEOUT=15
			KEEPALIVE_TIME=600
			KEEPALIVE_INTVL=60
			KEEPALIVE_PROBES=5
			;;
		balanced)
			# 均衡模式：适度优化
			SWAPPINESS=30
			DIRTY_RATIO=20
			DIRTY_BG_RATIO=10
			OVERCOMMIT=0
			VFS_PRESSURE=75
			RMEM_MAX=16777216
			WMEM_MAX=16777216
			TCP_RMEM="4096 87380 16777216"
			TCP_WMEM="4096 65536 16777216"
			SOMAXCONN=4096
			BACKLOG=5000
			SYN_BACKLOG=4096
			PORT_RANGE="1024 49151"
			SCHED_AUTOGROUP=1
			THP="always"
			NUMA=1
			FIN_TIMEOUT=30
			KEEPALIVE_TIME=600
			KEEPALIVE_INTVL=60
			KEEPALIVE_PROBES=5
			;;
	esac

	# ── 根据内存大小自适应调整 ──
	if [ "$MEM_MB" -ge 16384 ]; then
		MIN_FREE_KB=131072
		[ "$scene" != "balanced" ] && SWAPPINESS=5
	elif [ "$MEM_MB" -ge 4096 ]; then
		MIN_FREE_KB=65536
	elif [ "$MEM_MB" -ge 1024 ]; then
		MIN_FREE_KB=32768
		# 小内存缩小缓冲区
		if [ "$scene" != "balanced" ]; then
			RMEM_MAX=16777216
			WMEM_MAX=16777216
			TCP_RMEM="4096 87380 16777216"
			TCP_WMEM="4096 65536 16777216"
		fi
	else
		MIN_FREE_KB=16384
		SWAPPINESS=30
		OVERCOMMIT=0
		RMEM_MAX=4194304
		WMEM_MAX=4194304
		TCP_RMEM="4096 32768 4194304"
		TCP_WMEM="4096 32768 4194304"
		SOMAXCONN=1024
		BACKLOG=1000
	fi

	# ── 直播场景额外：UDP 缓冲区加大 ──
	local STREAM_EXTRA=""
	if [ "$scene" = "stream" ]; then
		STREAM_EXTRA="
# 直播推流 UDP 优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384"
	fi

	# ── 游戏服场景额外：低延迟优先 ──
	local GAME_EXTRA=""
	if [ "$scene" = "game" ]; then
		GAME_EXTRA="
# 游戏服低延迟优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0"
	fi

	# ── 加载 BBR 模块 ──
	local CC="bbr"
	local QDISC="fq"
	local KVER
	KVER=$(uname -r | grep -oP '^\d+\.\d+')
	if printf '%s\n%s' "4.9" "$KVER" | sort -V -C; then
		if ! lsmod 2>/dev/null | grep -q tcp_bbr; then
			modprobe tcp_bbr 2>/dev/null
		fi
		if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
			CC="cubic"
			QDISC="fq_codel"
		fi
	else
		CC="cubic"
		QDISC="fq_codel"
	fi

	# ── 备份已有配置 ──
	[ -f "$CONF" ] && cp "$CONF" "${CONF}.bak.$(date +%s)"

	# ── 写入配置文件（持久化） ──
	echo -e "${gl_lv}写入优化配置...${gl_bai}"
	cat > "$CONF" << SYSCTL
# kejilion 内核调优配置
# 模式: $mode_name | 场景: $scene
# 内存: ${MEM_MB}MB | 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# ── TCP 拥塞控制 ──
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $CC

# ── TCP 缓冲区 ──
net.core.rmem_max = $RMEM_MAX
net.core.wmem_max = $WMEM_MAX
net.core.rmem_default = $(echo "$TCP_RMEM" | awk '{print $2}')
net.core.wmem_default = $(echo "$TCP_WMEM" | awk '{print $2}')
net.ipv4.tcp_rmem = $TCP_RMEM
net.ipv4.tcp_wmem = $TCP_WMEM

# ── 连接队列 ──
net.core.somaxconn = $SOMAXCONN
net.core.netdev_max_backlog = $BACKLOG
net.ipv4.tcp_max_syn_backlog = $SYN_BACKLOG

# ── TCP 连接优化 ──
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = $FIN_TIMEOUT
net.ipv4.tcp_keepalive_time = $KEEPALIVE_TIME
net.ipv4.tcp_keepalive_intvl = $KEEPALIVE_INTVL
net.ipv4.tcp_keepalive_probes = $KEEPALIVE_PROBES
net.ipv4.tcp_max_tw_buckets = 65536
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1

# ── 端口与内存 ──
net.ipv4.ip_local_port_range = $PORT_RANGE
net.ipv4.tcp_mem = $((MEM_MB * 1024 / 8)) $((MEM_MB * 1024 / 4)) $((MEM_MB * 1024 / 2))
net.ipv4.tcp_max_orphans = 32768

# ── 虚拟内存 ──
vm.swappiness = $SWAPPINESS
vm.dirty_ratio = $DIRTY_RATIO
vm.dirty_background_ratio = $DIRTY_BG_RATIO
vm.overcommit_memory = $OVERCOMMIT
vm.min_free_kbytes = $MIN_FREE_KB
vm.vfs_cache_pressure = $VFS_PRESSURE

# ── CPU/内核调度 ──
kernel.sched_autogroup_enabled = $SCHED_AUTOGROUP
$([ -f /proc/sys/kernel/numa_balancing ] && echo "kernel.numa_balancing = $NUMA" || echo "# numa_balancing 不支持")

# ── 安全防护 ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ── 文件描述符 ──
fs.file-max = 1048576
fs.nr_open = 1048576

# ── 连接跟踪 ──
$(if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
echo "net.netfilter.nf_conntrack_max = $((SOMAXCONN * 32))"
echo "net.netfilter.nf_conntrack_tcp_timeout_established = 7200"
echo "net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30"
echo "net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15"
echo "net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 15"
else
echo "# conntrack 未启用"
fi)
$STREAM_EXTRA
$GAME_EXTRA
SYSCTL

	# ── 应用配置 ──
	echo -e "${gl_lv}应用优化参数...${gl_bai}"
	sysctl -p "$CONF" 2>&1 | grep -v "^$\|^net\.\|^vm\.\|^fs\.\|^kernel\." || true

	# ── 透明大页面 ──
	if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
		echo "$THP" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
	fi

	# ── 文件描述符限制 ──
	if ! grep -q "# kejilion-optimize" /etc/security/limits.conf 2>/dev/null; then
		cat >> /etc/security/limits.conf << 'LIMITS'

# kejilion-optimize
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS
	fi

	# ── BBR 持久化 ──
	if [ "$CC" = "bbr" ]; then
		echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null
		# 清理旧的 sysctl.conf 里的 bbr 配置（避免冲突）
		sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
	fi

	echo -e "${gl_lv}${mode_name} 优化完成！配置已持久化到 ${CONF}${gl_bai}"
	echo -e "${gl_lv}内存: ${MEM_MB}MB | 拥塞算法: ${CC} | 队列: ${QDISC}${gl_bai}"
}

# ── 各模式入口函数（保持原有调用接口不变） ──

optimize_high_performance() {
	_kernel_optimize_core "${tiaoyou_moshi:-高性能优化模式}" "high"
}

optimize_balanced() {
	_kernel_optimize_core "均衡优化模式" "balanced"
}

optimize_web_server() {
	_kernel_optimize_core "网站搭建优化模式" "web"
}

# ── 还原默认设置（完全清理） ──
restore_defaults() {
	echo -e "${gl_lv}还原到默认设置...${gl_bai}"

	local CONF="/etc/sysctl.d/99-kejilion-optimize.conf"

	# 删除优化配置文件
	rm -f "$CONF"

	# 清理 sysctl.conf 里可能残留的 bbr 配置
	sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null

	# 重新加载系统默认配置
	sysctl --system 2>&1 | tail -1

	# 还原透明大页面
	[ -f /sys/kernel/mm/transparent_hugepage/enabled ] && \
		echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null

	# 清理文件描述符配置
	if grep -q "# kejilion-optimize" /etc/security/limits.conf 2>/dev/null; then
		sed -i '/# kejilion-optimize/,+4d' /etc/security/limits.conf
	fi

	# 清理 BBR 持久化
	rm -f /etc/modules-load.d/bbr.conf 2>/dev/null

	echo -e "${gl_lv}系统已还原到默认设置${gl_bai}"
}


Kernel_optimize() {
	root_use
	while true; do
	  clear
	  send_stats "Linux内核调优管理"
	  echo "Linux系统内核参数优化"
	  echo "视频介绍: https://www.bilibili.com/video/BV1Kb421J7yg?t=0.1"
	  echo "------------------------------------------------"
	  echo "提供多种系统参数调优模式，用户可以根据自身使用场景进行选择切换。"
	  echo -e "${gl_huang}提示: ${gl_bai}生产环境请谨慎使用！"
	  echo -e "--------------------"
	  echo -e "1. 高性能优化模式：     最大化系统性能，激进的内存和网络参数。"
	  echo -e "2. 均衡优化模式：       在性能与资源消耗之间取得平衡，适合日常使用。"
	  echo -e "3. 网站优化模式：       针对网站服务器优化，超高并发连接队列。"
	  echo -e "4. 直播优化模式：       针对直播推流优化，UDP 缓冲区加大，减少延迟。"
	  echo -e "5. 游戏服优化模式：     针对游戏服务器优化，低延迟优先。"
	  echo -e "6. 还原默认设置：       将系统设置还原为默认配置。"
	  echo -e "7. 自动调优：           根据测试数据自动调优内核参数。${gl_huang}★${gl_bai}"
	  echo "--------------------"
	  echo "0. 返回上一级选单"
	  echo "--------------------"
	  read -e -p "请输入你的选择: " sub_choice
	  case $sub_choice in
		  1)
			  cd ~
			  clear
			  local tiaoyou_moshi="高性能优化模式"
			  optimize_high_performance
			  send_stats "高性能模式优化"
			  ;;
		  2)
			  cd ~
			  clear
			  optimize_balanced
			  send_stats "均衡模式优化"
			  ;;
		  3)
			  cd ~
			  clear
			  optimize_web_server
			  send_stats "网站优化模式"
			  ;;
		  4)
			  cd ~
			  clear
			  _kernel_optimize_core "直播优化模式" "stream"
			  send_stats "直播推流优化"
			  ;;
		  5)
			  cd ~
			  clear
			  _kernel_optimize_core "游戏服优化模式" "game"
			  send_stats "游戏服优化"
			  ;;
		  6)
			  cd ~
			  clear
			  restore_defaults
			  curl -sS ${gh_proxy}raw.githubusercontent.com/kejilion/sh/refs/heads/main/network-optimize.sh -o /tmp/network-optimize.sh && source /tmp/network-optimize.sh && restore_network_defaults
			  send_stats "还原默认设置"
			  ;;

		  7)
			  cd ~
			  clear
			  curl -sS ${gh_proxy}raw.githubusercontent.com/kejilion/sh/refs/heads/main/network-optimize.sh | bash
			  send_stats "内核自动调优"
			  ;;

		  *)
			  break
			  ;;
	  esac
	  break_end
	done
}
