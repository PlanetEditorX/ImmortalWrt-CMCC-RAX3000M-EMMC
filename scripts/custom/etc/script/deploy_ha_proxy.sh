#!/bin/sh

### === 用户配置区域 === ###
VIP="192.168.1.5"
MAIN_ROUTER="192.168.1.2"
PROXY_ROUTER="192.168.1.3"
INTERFACE="eth0"
### ===================== ###

echo "[HA-Deploy] 开始部署旁路由高可用架构..."

### 1. 系统参数
echo "net.ipv4.ip_nonlocal_bind=1" >> /etc/sysctl.conf
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
echo "[HA-Deploy] nftables 配置完成"

### 3. Keepalived 配置
mkdir -p /etc/keepalived

cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state MASTER
    interface $INTERFACE
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        $VIP
    }
    notify_master "/etc/keepalived/vip_up.sh"
    notify_backup "/etc/keepalived/vip_down.sh"
    notify_fault "/etc/keepalived/vip_down.sh"
}
EOF

### 4. VIP 漂移脚本
cat <<EOF > /etc/keepalived/vip_up.sh
#!/bin/sh
logger -t keepalived "VIP $VIP 已绑定，旁路由接管"
ip addr add $VIP/24 dev $INTERFACE
EOF

cat <<EOF > /etc/keepalived/vip_down.sh
#!/bin/sh
logger -t keepalived "VIP $VIP 已解绑，回退主路由"
ip addr del $VIP/24 dev $INTERFACE
EOF

chmod +x /etc/keepalived/vip_*.sh
echo "[HA-Deploy] VIP 漂移脚本已配置"

### 5. 自动启动脚本
cat <<EOF > /etc/keepalived/keepalived_boot.sh
#!/bin/sh
CONF_SRC="/etc/keepalived/keepalived.conf"
CONF_DST="/tmp/keepalived.conf"
KEEPALIVED_BIN="/usr/sbin/keepalived"
LOG="/tmp/keepalived_boot.log"

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

sleep 2

if ip addr show "$INTERFACE" | grep -q "$VIP"; then
    echo "[INFO] VIP $VIP 已绑定" >> "\$LOG"
else
    echo "[WARN] VIP $VIP 未绑定，尝试手动绑定" >> "\$LOG"
    ip addr add "$VIP"/24 dev "$INTERFACE" && \
    echo "[INFO] VIP 手动绑定成功" >> "\$LOG" || \
    echo "[ERROR] VIP 手动绑定失败" >> "\$LOG"
fi
EOF

chmod +x /etc/keepalived/keepalived_boot.sh

### 6. 添加到 rc.local
sed -i '/keepalived_boot.sh/d' /etc/rc.local
sed -i '/exit 0/i /etc/keepalived/keepalived_boot.sh' /etc/rc.local
echo "[HA-Deploy] 已添加开机启动"
echo "[HA-Deploy] 部署完成 ✅ 请重启设备验证 VIP 是否绑定成功"
