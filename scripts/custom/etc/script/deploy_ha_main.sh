#!/bin/sh

### === 用户配置区域 === ###
VIP="192.168.1.5"
INTERFACE="br-lan"
PRIORITY="50"
PEER_IP="192.168.1.3"
FAIL_THRESHOLD=3
RECOVER_THRESHOLD=2
CHECK_INTERVAL=5
### ===================== ###

echo "[HA-Main] 开始部署主路由高可用配置..."

### 1. 系统参数
grep -q '^net.ipv4.ip_nonlocal_bind=1$' /etc/sysctl.conf || echo 'net.ipv4.ip_nonlocal_bind=1' >> /etc/sysctl.conf
sysctl -p

### 2. nftables 防火墙
cat <<EOF > /etc/nftables.conf
table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;

        ct state established,related accept
        iifname "lo" accept
        ip protocol icmp accept
        ip protocol 112 accept  # VRRP
    }
}
EOF
nft -f /etc/nftables.conf
echo "[HA-Main] nftables 配置完成"

### 3. Keepalived 配置
mkdir -p /etc/keepalived

cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state BACKUP
    interface $INTERFACE
    virtual_router_id 51
    priority $PRIORITY
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        $VIP
    }
}
EOF

### 4. 漂移检测脚本（嵌入变量）
cat <<EOF > /etc/keepalived/failover_watchdog.sh
#!/bin/sh

VIP="$VIP"
INTERFACE="$INTERFACE"
PEER_IP="$PEER_IP"
FAIL_THRESHOLD=$FAIL_THRESHOLD
RECOVER_THRESHOLD=$RECOVER_THRESHOLD
CHECK_INTERVAL=$CHECK_INTERVAL

LOG="/tmp/log/failover_watchdog.log"
FAIL_COUNT=0
RECOVER_COUNT=0
MAX_SIZE=1048576 # 1MB

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG"
}

log "[Watchdog] 启动监控脚本..."

rotate_log() {
    if [ -f "\$LOG" ] && [ "\$(wc -c < "\$LOG")" -ge "\$MAX_SIZE" ]; then
        tail -n 20 "\$LOG" > "\$LOG"
        log "[Watchdog] 日志已清理，保留最近 20 行"
    fi
}

while true; do
    if ping -c 1 -W 1 -n -q "\$PEER_IP" >/dev/null 2>&1; then
        log "[Watchdog] 旁路由 \$PEER_IP 在线"
        FAIL_COUNT=0
        RECOVER_COUNT=\$((RECOVER_COUNT + 1))

        if ip -4 addr show "\$INTERFACE" | grep -q "\$VIP" && [ "\$RECOVER_COUNT" -ge "\$RECOVER_THRESHOLD" ]; then
            log "[Watchdog] 旁路由恢复，解绑 VIP \$VIP"
            ip addr del "\$VIP/32" dev "\$INTERFACE"
            RECOVER_COUNT=0
            log "[Watchdog] 关闭主路由openclash"
            /etc/init.d/openclash stop
            uci set openclash.config.enable='0'
            uci commit openclash
        fi
    else
        log "[Watchdog] 旁路由 \$PEER_IP 失联"
        RECOVER_COUNT=0
        FAIL_COUNT=\$((FAIL_COUNT + 1))

        if ! ip -4 addr show "\$INTERFACE" | grep -q "\$VIP" && [ "\$FAIL_COUNT" -ge "\$FAIL_THRESHOLD" ]; then
            log "[Watchdog] 接管 VIP \$VIP"
            ip addr add "\$VIP/32" dev "\$INTERFACE"
            FAIL_COUNT=0
            log "[Watchdog] 启动主路由openclash"
            uci set openclash.config.enable='1'
            uci commit openclash
            /etc/init.d/openclash start
            uci set openclash.config.enable='0'
            uci commit openclash
        fi
    fi

    rotate_log
    sleep "\$CHECK_INTERVAL"
done
EOF

chmod +x /etc/keepalived/failover_watchdog.sh

### 5. 自动启动脚本
cat <<EOF > /etc/keepalived/keepalived_boot.sh
#!/bin/sh
CONF_SRC="/etc/keepalived/keepalived.conf"
CONF_DST="/tmp/keepalived.conf"
KEEPALIVED_BIN="/usr/sbin/keepalived"
LOG="/tmp/log/keepalived_boot_main.log"

echo "== keepalived_boot.sh 被调用 ==" >> "\$LOG"

if [ -f "\$CONF_SRC" ]; then
    cp "\$CONF_SRC" "\$CONF_DST"
    echo "[INFO] 配置文件已复制到 \$CONF_DST" >> "\$LOG"
else
    echo "[ERROR] 配置文件不存在：\$CONF_SRC" >> "\$LOG"
    exit 1
fi

"\$KEEPALIVED_BIN" -n -f "\$CONF_DST" &
echo "[INFO] Keepalived 已启动" >> "\$LOG"

/etc/keepalived/failover_watchdog.sh &
echo "[INFO] Watchdog 已启动" >> "\$LOG"
EOF

chmod +x /etc/keepalived/keepalived_boot.sh

### 6. 添加到 rc.local
sed -i '/keepalived_boot.sh/d' /etc/rc.local
sed -i '/exit 0/i /etc/keepalived/keepalived_boot.sh' /etc/rc.local
echo "[HA-Main] 已添加开机启动"

### 7. 可选：封装为 init.d 服务（OpenWrt/ImmortalWrt）
cat <<EOF > /etc/init.d/failover_watchdog
#!/bin/sh /etc/rc.common
START=99

start() {
    echo "[init.d] 启动 failover_watchdog"
    /etc/keepalived/failover_watchdog.sh &
}
EOF

chmod +x /etc/init.d/failover_watchdog
/etc/init.d/failover_watchdog enable

echo "[HA-Main] 主路由部署完成 ✅ 请重启设备验证 VIP 漂移逻辑是否生效"