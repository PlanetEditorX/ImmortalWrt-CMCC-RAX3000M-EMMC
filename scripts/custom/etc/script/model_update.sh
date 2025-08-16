#!/bin/sh

# 定义 OpenClash 目录和相关路径
OPENCLASH_DIR="/etc/openclash"
OPENCLASH_INIT_SCRIPT="/etc/init.d/openclash"
LOG_FILE="/var/log/model_update.log" # 添加日志文件以便调试
GIT_DIR="/tmp/openclash"
GIT_PATH="git@github.com:PlanetEditorX/openclash.git"

# 函数：记录日志
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "--- Script started ---"

# --- 检查文件大小 ---
SMART_WEIGHT_FILE="$OPENCLASH_DIR/smart_weight_data.csv"
FILE_SIZE_B=0
if [ -f "$SMART_WEIGHT_FILE" ]; then
    FILE_SIZE_B=$(ls -l "$SMART_WEIGHT_FILE" | awk '{print $5}')
    log_message "File size of $SMART_WEIGHT_FILE is $FILE_SIZE_B bytes."
else
    log_message "File $SMART_WEIGHT_FILE does not exist. Exiting."
    exit 0
fi

if [ "$FILE_SIZE_B" -le 10240 ]; then
    log_message "File size is <= 10KB. No action needed. Exiting."
    exit 0
fi

log_message "File size is > 10KB. Continuing with update process."
# --- 文件大小检查结束 ---

# 步骤 1: 拉取最新镜像
log_message "Pull the latest image..."
if test -d "$GIT_DIR"; then
    log_message "Directory '$GIT_DIR' exists."
    cd "$GIT_DIR"
    # 获取远程所有分支的最新状态
    git fetch --all >> "$LOG_FILE" 2>&1
    # 将本地 main 分支强制重置到远程 origin/main 的最新状态，并丢弃所有本地修改
    git reset --hard origin/main >> "$LOG_FILE" 2>&1
else
    # 重启后/tmp被清空
    log_message "Directory '$GIT_DIR' does not exist."
    git clone --depth 1 "$GIT_PATH" "$GIT_DIR" >> "$LOG_FILE" 2>&1
fi

cd "$GIT_DIR" || { log_message "Error: Cannot change directory to $GIT_DIR. Exiting."; exit 1; }

log_message "Move $OPENCLASH_DIR/smart_weight_data.csv to $GIT_DIR..."
mv "$OPENCLASH_DIR/smart_weight_data.csv" "$GIT_DIR" >> "$LOG_FILE" 2>&1
ls -l "$GIT_DIR/smart_weight_data.csv" >> "$LOG_FILE" 2>&1

log_message "Adding all changes..."
git add . >> "$LOG_FILE" 2>&1
COMMIT_MESSAGE="Auto Update in $(date '+%Y-%m-%d %H:%M:%S')"
log_message "Committing local changes: $COMMIT_MESSAGE"
git commit -m "$COMMIT_MESSAGE" >> "$LOG_FILE" 2>&1
sleep 5

# 步骤 2: 推送本地更改到远程仓库
log_message "Pushing local changes to remote repository..."
git push >> "$LOG_FILE" 2>&1

# 等待一定时间后拉取更新
sleep 120

# 步骤 3: 再次拉取最新代码
log_message "Pulling latest changes again..."
# --- git pull 开始 ---
SECOND_PULL_SUCCESS=0
for i in $(seq 1 3); do
    log_message "Attempt $i of 3: Pulling latest changes again..."
    # Capture git pull output to a variable and log it
    GIT_OUTPUT=$(git pull 2>&1 | tee -a "$LOG_FILE")
    if [ $? -eq 0 ]; then
        # Check if the output contains "Already up to date"
        if echo "$GIT_OUTPUT" | grep -q "Already up to date"; then
            log_message "Second git pull succeeded but no updates on attempt $i. Retrying in 60 seconds..."
            sleep 60 # Wait 60 seconds before retrying
        else
            log_message "Second git pull successful with updates on attempt $i."
            SECOND_PULL_SUCCESS=1
            break # Exit loop on successful pull with updates
        fi
    else
        log_message "Second git pull failed on attempt $i. Retrying in 30 seconds..."
        sleep 60 # Wait 60 seconds before retrying
    fi
done

if [ "$SECOND_PULL_SUCCESS" -eq 0 ]; then
    log_message "Error: Second git pull failed after 3 attempts. Continuing script but be aware."
fi

sleep 10

# --- git pull 结束 ---

# 步骤 4: 拷贝模型
log_message "Copy $GIT_DIR/Model.bin to $OPENCLASH_DIR..."
cp "$GIT_DIR/Model.bin" "$OPENCLASH_DIR" >> "$LOG_FILE" 2>&1

# --- 检查 OpenClash 服务状态并决定是否重启 ---
log_message "Checking OpenClash service status..."
if pgrep -f "openclash" >/dev/null; then
    log_message "OpenClash service is running. Restarting service..."
    "$OPENCLASH_INIT_SCRIPT" restart >> "$LOG_FILE" 2>&1
else
    log_message "OpenClash service is not running. Skipping restart."
fi

# --- 服务状态检查结束 ---
log_message "--- Script finished ---"