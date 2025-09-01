#!/usr/bin/env fish

# ====================================================================
# Update emacs-everywhere and restart Emacs service (Fish version)
# 更新 emacs-everywhere 并重启 Emacs 服务 (Fish 版本)
# ====================================================================

# Colors for output / 输出颜色
set RED '\033[0;31m'
set GREEN '\033[0;32m'
set YELLOW '\033[1;33m'
set BLUE '\033[0;34m'
set NC '\033[0m' # No Color / 无颜色

# Function to print colored messages / 彩色输出函数
function print_info
    echo -e "$BLUE""[INFO]""$NC $argv"
end

function print_success
    echo -e "$GREEN""[SUCCESS]""$NC $argv"
end

function print_warning
    echo -e "$YELLOW""[WARNING]""$NC $argv"
end

function print_error
    echo -e "$RED""[ERROR]""$NC $argv"
end

# ====================================================================
# Step 1: Update straight.el managed emacs-everywhere repository
# 步骤 1: 更新 straight.el 管理的 emacs-everywhere 仓库
# ====================================================================

print_info "Updating emacs-everywhere repository..."
print_info "更新 emacs-everywhere 仓库..."

set STRAIGHT_REPO_DIR "$HOME/.emacs.d/straight/repos/emacs-everywhere"

if not test -d "$STRAIGHT_REPO_DIR"
    print_error "Straight repository not found at: $STRAIGHT_REPO_DIR"
    print_error "未找到 Straight 仓库: $STRAIGHT_REPO_DIR"
    exit 1
end

cd "$STRAIGHT_REPO_DIR"

# Fetch latest changes / 获取最新更改
print_info "Fetching from origin..."
git fetch origin

# Check current status / 检查当前状态
set CURRENT_BRANCH (git branch --show-current)
print_info "Current branch: $CURRENT_BRANCH"

# Check if there are diverged commits / 检查是否有分歧的提交
set LOCAL_COMMIT (git rev-parse HEAD)
set REMOTE_COMMIT (git rev-parse origin/$CURRENT_BRANCH)

if test "$LOCAL_COMMIT" != "$REMOTE_COMMIT"
    print_warning "Local and remote have diverged. Resetting to origin/$CURRENT_BRANCH..."
    print_warning "本地和远程有分歧。重置到 origin/$CURRENT_BRANCH..."
    
    # Reset to remote / 重置到远程版本
    git reset --hard origin/$CURRENT_BRANCH
    print_success "Repository reset to latest version"
    print_success "仓库已重置到最新版本"
else
    print_info "Repository is already up to date"
    print_info "仓库已是最新"
end

# Show current commit / 显示当前提交
echo ""
print_info "Current commit:"
git log --oneline -1

# ====================================================================
# Step 2: Rebuild emacs-everywhere with straight.el
# 步骤 2: 使用 straight.el 重新构建 emacs-everywhere
# ====================================================================

echo ""
print_info "Rebuilding emacs-everywhere package..."
print_info "重新构建 emacs-everywhere 包..."

emacs --batch --load ~/.emacs.d/init.el --eval '
(progn
  (straight-rebuild-package "emacs-everywhere")
  (message "Successfully rebuilt emacs-everywhere")
  (message "成功重建 emacs-everywhere"))
' 2>&1 | grep -v "^Loading"

if test $status -eq 0
    print_success "Package rebuilt successfully"
    print_success "包重建成功"
else
    print_error "Failed to rebuild package"
    print_error "包重建失败"
    exit 1
end

# ====================================================================
# Step 3: Restart Emacs service (nix-darwin)
# 步骤 3: 重启 Emacs 服务 (nix-darwin)
# ====================================================================

echo ""
print_info "Restarting Emacs service..."
print_info "重启 Emacs 服务..."

# Check if service exists / 检查服务是否存在
set SERVICE_NAME "org.nixos.emacs"
set OLD_PID (launchctl list | grep "$SERVICE_NAME" | awk '{print $1}')

if test -z "$OLD_PID"; or test "$OLD_PID" = "-"
    print_warning "Emacs service not running or not found"
    print_warning "Emacs 服务未运行或未找到"
else
    print_info "Current Emacs daemon PID: $OLD_PID"
    
    # Stop service / 停止服务
    launchctl stop "$SERVICE_NAME"
    sleep 1
    
    # Start service / 启动服务
    launchctl start "$SERVICE_NAME"
    sleep 2
    
    # Verify new PID / 验证新 PID
    set NEW_PID (launchctl list | grep "$SERVICE_NAME" | awk '{print $1}')
    
    if test -n "$NEW_PID"; and test "$NEW_PID" != "-"; and test "$NEW_PID" != "$OLD_PID"
        print_success "Emacs service restarted (PID: $OLD_PID → $NEW_PID)"
        print_success "Emacs 服务已重启 (PID: $OLD_PID → $NEW_PID)"
    else
        print_error "Failed to restart Emacs service"
        print_error "重启 Emacs 服务失败"
        exit 1
    end
end

# ====================================================================
# Step 4: Verify the update
# 步骤 4: 验证更新
# ====================================================================

echo ""
print_info "Verifying update..."
print_info "验证更新..."

# Check if emacsclient can connect / 检查 emacsclient 是否能连接
if not emacsclient --eval '(emacs-version)' > /dev/null 2>&1
    print_error "Cannot connect to Emacs daemon"
    print_error "无法连接到 Emacs daemon"
    exit 1
end

# Check emacs-everywhere status / 检查 emacs-everywhere 状态
set LOADED (emacsclient --eval '(if (featurep \'emacs-everywhere) "yes" "no")' 2>/dev/null | tr -d '"')
if test "$LOADED" = "yes"
    print_success "emacs-everywhere is loaded"
    print_success "emacs-everywhere 已加载"
else
    print_warning "emacs-everywhere is not loaded (may need manual loading)"
    print_warning "emacs-everywhere 未加载（可能需要手动加载）"
end

# Check for removed functions (verify simplified version) / 检查已移除的函数（验证简化版本）
set HAS_MARKDOWN (emacsclient --eval '(if (fboundp \'emacs-everywhere-markdown-p) "yes" "no")' 2>/dev/null | tr -d '"')
if test "$HAS_MARKDOWN" = "no"
    print_success "Simplified version confirmed (markdown support removed)"
    print_success "确认为简化版本（markdown 支持已移除）"
else
    print_warning "Old version may still be loaded"
    print_warning "可能仍在使用旧版本"
end

# ====================================================================
# Summary / 总结
# ====================================================================

echo ""
echo "======================================================================"
print_success "Update completed! / 更新完成！"
echo "======================================================================"
echo ""
print_info "Build location / 构建位置: ~/.emacs.d/straight/build/emacs-everywhere/"
print_info "Repository / 仓库: ~/.emacs.d/straight/repos/emacs-everywhere/"
echo ""
print_info "If emacs-everywhere is not loaded, run in Emacs:"
print_info "如果 emacs-everywhere 未加载，在 Emacs 中运行："
echo "  (straight-use-package 'emacs-everywhere)"
echo ""
