#!/bin/sh

# ==============以下是广告过滤规则拉取脚本=================

LOG_FILE="/var/log/adguard_github520.log" # 推荐添加日志文件以便调试

# 函数：记录日志
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "--- Script started ---"

MAX_WAIT_TIME=30
WAIT_INTERVAL=2
elapsed_time=0

# Check OpenClash status
if /etc/init.d/openclash status | grep -q "Syntax:"; then
    log_message "[广告过滤规则拉取脚本] 正在检测 OpenClash 运行状态..."
    log_message "[广告过滤规则拉取脚本] 等待 10 秒以确保 OpenClash 已启动..."
    sleep 10
else
    log_message "[广告过滤规则拉取脚本] 正在检测 OpenClash 运行状态..."
    while ! /etc/init.d/openclash status | grep -q "running"; do
        if [ "$elapsed_time" -ge "$MAX_WAIT_TIME" ]; then
            log_message "[广告过滤规则拉取脚本] 未能在 10 秒内检测到 OpenClash 运行状态，脚本已停止运行..."
            exit 1
        fi
        sleep "$WAIT_INTERVAL"
        elapsed_time=$((elapsed_time + WAIT_INTERVAL))
    done
    log_message "[广告过滤规则拉取脚本] 检测到 OpenClash 正在运行，10 秒后开始拉取规则..."
    sleep 10
fi

# Dynamically select dnsmasq directory
log_message "[广告过滤规则拉取脚本] 开始检测 dnsmasq 规则目录..."
UCI_OUTPUT=$(uci show dhcp.@dnsmasq[0] 2>/dev/null)

# Detect new firmware (hash ID mode)
if echo "$UCI_OUTPUT" | grep -qE 'cfg[0-9a-f]{6}'; then
    HASH_ID=$(echo "$UCI_OUTPUT" | grep -oE 'cfg[0-9a-f]{6}' | head -1)
    TARGET_DIR="/tmp/dnsmasq.${HASH_ID}.d"
    log_message "[广告过滤规则拉取脚本] 当前 dnsmasq 规则目录: $TARGET_DIR"
# Detect old firmware (numeric index mode)
elif echo "$UCI_OUTPUT" | grep -qE '@dnsmasq\[[0-9]+]'; then
    TARGET_DIR="/tmp/dnsmasq.d"
    log_message "[广告过滤规则拉取脚本] 当前dnsmasq 规则目录: $TARGET_DIR"
# Compatibility fallback
else
    TARGET_DIR=$(find /tmp -maxdepth 1 -type d -name "dnsmasq.*.d" | head -n 1)
    if [ -z "$TARGET_DIR" ]; then
        log_message "[广告过滤规则拉取脚本] 错误：未找到有效的 dnsmasq 规则目录，脚本已停止！"
        exit 1
    fi
    log_message "[广告过滤规则拉取脚本] 检测失败，使用已存在的 dnsmasq 规则目录: $TARGET_DIR"
fi

# Verify directory existence and create if not found
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi

# Log clearance of existing ad filtering rules
log_message "[广告过滤规则拉取脚本] 清除已有规则…"
# Only delete ad rule files in the current target directory
rm -f "$TARGET_DIR"/*ad*.conf
# Remove old ad rules from /etc/hosts marked by specific comments
sed -i '/# AWAvenue-Ads-Rule Start/,/# AWAvenue-Ads-Rule End/d' /etc/hosts
sed -i '/# GitHub520 Host Start/,/# GitHub520 Host End/d' /etc/hosts

log_message "[广告过滤规则拉取脚本] 拉取最新的 anti-AD 广告过滤规则，规则体积较大，请耐心等候…"
# Check if /tmp/anti-ad-for-dnsmasq.conf exists (for local copy fallback)
if [ -f /tmp/anti-ad-for-dnsmasq.conf ]; then
    # If file exists, copy it, redirecting stdout and stderr to null/log
    cp /tmp/anti-ad-for-dnsmasq.conf "$TARGET_DIR/anti-ad-for-dnsmasq.conf" >/dev/null 2>/tmp/anti-ad-curl.log
    CURL_EXIT=0
else
    # If file doesn't exist, download it using curl, redirecting output
    curl -sS -4 -L --retry 10 --retry-delay 2 "https://testingcf.jsdelivr.net/gh/privacy-protection-tools/anti-AD@refs/heads/master/adblock-for-dnsmasq.conf" -o "$TARGET_DIR/anti-ad-for-dnsmasq.conf" >/dev/null 2>/tmp/anti-ad-curl.log
    CURL_EXIT=$?
fi

if [ "$CURL_EXIT" -eq 0 ]; then
    log_message "[广告过滤规则拉取脚本] anti-AD 规则拉取成功！保存路径：${TARGET_DIR}/anti-ad-for-dnsmasq.conf"
else
    log_message "[广告过滤规则拉取脚本] anti-AD 规则拉取失败 (错误码:$CURL_EXIT)，查看 /tmp/anti-ad-curl.log 获取详细信息。"
    echo "CURL Exit Code: $CURL_EXIT" >> /tmp/anti-ad-curl.log
fi

log_message "[广告过滤规则拉取脚本] 拉取最新的 GitHub520 加速规则…"
# Check if /tmp/github520 exists (for local copy fallback)
if [ -f /tmp/github520 ]; then
    # If file exists, append its content to /etc/hosts
    cat /tmp/github520 >> /etc/hosts 2>/tmp/github520-curl.log
    CURL_EXIT_GH=0
else
    # If file doesn't exist, download and append to /etc/hosts
    curl -4 -sSL --retry 10 --retry-delay 2 "https://raw.hellogithub.com/hosts" >> /etc/hosts 2>/tmp/github520-curl.log
    CURL_EXIT_GH=$?
fi

if [ "$CURL_EXIT_GH" -eq 0 ]; then
    log_message "[广告过滤规则拉取脚本] GitHub520 加速规则拉取成功！已追加到 /etc/hosts 文件中。"
else
    log_message "[广告过滤规则拉取脚本] GitHub520 加速规则拉取失败 (错误码:$CURL_EXIT_GH)，查看 /tmp/github520-curl.log 获取详细信息。"
    echo "CURL Exit Code: $CURL_EXIT_GH" >> /tmp/github520-curl.log
fi

log_message "[广告过滤规则拉取脚本] 清理 DNS 缓存..."
/etc/init.d/dnsmasq stop
/etc/init.d/dnsmasq start
log_message "[广告过滤规则拉取脚本] 脚本运行完毕!"
