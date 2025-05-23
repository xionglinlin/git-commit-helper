#!/bin/bash
set -e

# 检查系统是否支持apt命令
check_apt_system() {
    command -v apt >/dev/null 2>&1
}

# 检查apt仓库中rust的版本
check_apt_rust_version() {
    local required_version="1.70.0"
    # 更新apt缓存
    sudo apt-get update || return 1
    # 检查rust包是否存在
    if ! apt-cache show rustc >/dev/null 2>&1; then
        echo "apt仓库中未找到 rust 包"
        return 1
    fi
    # 获取仓库中的版本信息
    local policy_output
    policy_output=$(apt-cache policy rustc)
    echo "仓库版本信息:"
    echo "$policy_output"

    # 获取仓库中的版本
    local repo_version=""
    if ! repo_version=$(echo "$policy_output" | grep -oP 'Candidate:\s*\K[^-\s]+'); then
        echo "无法获取仓库中的 rust 版本信息"
        return 1
    fi

    if [ -z "$repo_version" ]; then
        echo "仓库中未找到可用的 rust 版本"
        return 1
    fi

    echo "解析到的版本号: $repo_version"

    if printf '%s\n%s' "$repo_version" "$required_version" | sort -V | head -n1 | grep -q "$required_version"; then
        echo "apt仓库中的 Rust 版本 ($repo_version) 满足要求"
        return 0
    else
        echo "apt仓库中的 Rust 版本 ($repo_version) 低于所需版本 ($required_version)"
        return 1
    fi
}

# 检查已安装的rust版本
check_rust_version() {
    local required_version="1.70.0"
    if ! command -v rustc >/dev/null 2>&1; then
        echo "未安装 Rust"
        return 1
    fi

    local current_version=$(rustc --version | cut -d' ' -f2)
    if printf '%s\n%s' "$current_version" "$required_version" | sort -V | head -n1 | grep -q "$required_version"; then
        return 0
    else
        echo "当前 Rust 版本 ($current_version) 低于所需版本 ($required_version)"
        return 1
    fi
}

# 使用apt安装rust
install_rust_via_apt() {
    echo "通过系统包管理器安装 rust..."
    sudo apt-get install -y rustc cargo || return 1
    return 0
}

# 初始化rustup环境
init_rustup() {
    echo "初始化 rustup..."

    # 检查rustup是否可用
    if ! command -v rustup >/dev/null 2>&1; then
        echo "错误: rustup 命令不可用"
        return 1
    fi

    # 显示rustup版本信息
    echo "rustup版本信息:"
    rustup -V

    # 检查当前安装的工具链
    echo "当前工具链信息:"
    if ! rustup show; then
        echo "警告: 无法显示工具链信息"
    fi

    # 设置默认工具链
    echo "设置默认工具链..."
    if ! rustup toolchain install stable --no-self-update; then
        echo "警告: 无法安装 stable 工具链"
        return 1
    fi

    if ! rustup default stable; then
        echo "错误: 无法设置默认工具链"
        return 1
    fi

    # 再次检查安装状态
    echo "安装后的工具链信息:"
    rustup show

    return 0
}

# 使用apt安装rustup
install_rustup_via_apt() {
    echo "通过系统包管理器安装 rustup..."
    sudo apt-get update && sudo apt-get install -y rustup || return 1

    echo "等待 rustup 准备就绪..."
    local max_attempts=5
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if command -v rustup >/dev/null 2>&1; then
            break
        fi
        echo "尝试 $attempt/$max_attempts: rustup 未就绪，等待..."
        sleep 2
        attempt=$((attempt + 1))
    done

    if ! command -v rustup >/dev/null 2>&1; then
        echo "错误: 安装后无法找到 rustup 命令"
        return 1
    fi

    return 0
}

# 从官网下载安装rustup
install_rustup_from_web() {
    echo "从官网下载 rustup..."
    if command -v wget >/dev/null 2>&1; then
        wget -O /tmp/rustup.sh --progress=bar:force:noscroll --show-progress https://sh.rustup.rs
        echo "安装 rustup..."
        sh /tmp/rustup.sh -y
        rm -f /tmp/rustup.sh
    else
        echo "使用 curl 下载..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    return 0
}

# 使用rustup安装rust
install_rust() {
    # 如果rustup不存在，先安装rustup
    if ! command -v rustup >/dev/null 2>&1; then
        if check_apt_system; then
            # 优先使用apt安装rustup
            if ! install_rustup_via_apt; then
                echo "通过apt安装rustup失败，尝试从官网下载安装..."
                install_rustup_from_web
            fi
        else
            install_rustup_from_web
        fi

        # 检查rustup安装是否成功
        if ! command -v rustup >/dev/null 2>&1; then
            echo "错误: rustup 安装失败"
            return 1
        fi

        init_rustup || return 1
    fi

    echo "设置 Rust 默认版本..."
    rustup default stable
}

# 在apt系统上检查并安装rust
if check_apt_system; then
    if ! check_rust_version; then
        echo "检查 apt 仓库中的 rust 版本..."
        if check_apt_rust_version; then
            # 仓库中的rust版本满足要求，直接使用apt安装
            echo "使用系统包管理器安装 rust..."
            install_rust_via_apt
        else
            # 仓库中的rust版本不满足要求，使用rustup安装
            echo "将使用 rustup 安装所需版本..."
            install_rust
        fi
    fi
fi

# 编译项目
cargo build --release

# 创建本地二进制目录
mkdir -p ~/.local/bin

# 安装二进制文件
cp ./target/release/git-commit-helper ~/.local/bin/
chmod +x ~/.local/bin/git-commit-helper

echo "二进制文件已安装到: ~/.local/bin/git-commit-helper"
echo "请运行以下命令完成配置:"
echo "  git-commit-helper config"

# 创建补全文件目录
mkdir -p ~/.local/share/bash-completion/completions
mkdir -p ~/.local/share/zsh/site-functions

# 安装补全文件
cp completions/git-commit-helper.bash ~/.local/share/bash-completion/completions/git-commit-helper
cp completions/git-commit-helper.zsh ~/.local/share/zsh/site-functions/_git-commit-helper

echo "补全文件已安装到:"
echo "  bash: ~/.local/share/bash-completion/completions/git-commit-helper"
echo "  zsh:  ~/.local/share/zsh/site-functions/_git-commit-helper"
echo "请重新加载 shell 配置文件以启用补全功能"
echo "  bash: source ~/.bashrc"
echo "  zsh:  source ~/.zshrc"

# 安装到当前 git 仓库
~/.local/bin/git-commit-helper install --force

echo "安装完成！"

# 添加打包功能
if [ "$1" = "package" ]; then
    case "$2" in
        "arch")
            makepkg -sf
            ;;
        "deb")
            dpkg-buildpackage -us -uc
            ;;
        "rpm")
            rpmbuild -ba git-commit-helper.spec
            ;;
        *)
            echo "用法: $0 package [arch|deb|rpm]"
            exit 1
            ;;
    esac
fi
