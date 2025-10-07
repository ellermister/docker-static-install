#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "错误: 请使用root权限运行此脚本"
    echo "使用方法: sudo $0"
    exit 1
fi

# 检查是否为apt系统
check_apt_system() {
    if ! command -v apt >/dev/null 2>&1 && ! command -v apt-get >/dev/null 2>&1; then
        echo "错误: 此脚本仅支持基于APT的系统 (Ubuntu/Debian)"
        echo "当前系统不支持apt包管理器"
        exit 1
    fi
    echo "✓ 检测到APT包管理系统"
}

# 检查并安装必需的依赖
install_dependencies() {
    echo "检查系统依赖..."
    
    # 需要检查的命令列表
    local commands=("wget" "curl" "tar" "systemctl" "iptables")
    local packages_to_install=()
    
    # 检查每个命令是否存在
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            case "$cmd" in
                "wget")
                    packages_to_install+=("wget")
                    ;;
                "curl")
                    packages_to_install+=("curl")
                    ;;
                "tar")
                    packages_to_install+=("tar")
                    ;;
                "systemctl")
                    packages_to_install+=("systemd")
                    ;;
                "iptables")
                    packages_to_install+=("iptables")
                    ;;
            esac
            echo "⚠ 缺少命令: $cmd"
        else
            echo "✓ $cmd 已安装"
        fi
    done
    
    # 如果有需要安装的包，则进行安装
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo "正在安装缺少的依赖: ${packages_to_install[*]}"
        apt update -qq
        apt install -y "${packages_to_install[@]}"
        
        # 再次检查安装是否成功
        for cmd in "${commands[@]}"; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                echo "错误: $cmd 安装失败"
                exit 1
            fi
        done
        echo "✓ 所有依赖安装完成"
    else
        echo "✓ 所有依赖已满足"
    fi
}

# 执行系统检查
echo "Docker静态安装脚本 - 系统检查"
echo "================================"
check_apt_system
install_dependencies
echo "================================"

cpuFamily=$(uname -m)
if [ $cpuFamily == "x86_64" ]; then
    cpuFamily="x86_64"
elif [ $cpuFamily == "aarch64" ]; then
    cpuFamily="aarch64"
else
    echo "Unsupported CPU architecture: $cpuFamily"
    exit 1
fi

githubRepo="https://raw.githubusercontent.com/ellermister/docker-static-install/refs/heads/main"
daemonFile="${githubRepo}/daemon.json"
dockerServiceFile="${githubRepo}/docker.service.conf"
mirror="https://download.docker.com/linux/static/stable/$cpuFamily/"

# 获取版本列表函数
get_docker_versions() {
    echo "正在获取Docker版本列表..."
    
    # 使用curl获取mirror页面内容
    page_content=$(curl -s "$mirror")
    
    if [ $? -ne 0 ]; then
        echo "错误: 无法访问Docker镜像站点"
        exit 1
    fi
    
    # 使用正则表达式提取所有docker版本（包括新版本docker-x.x.x.tgz和旧版本docker-x.x.x-ce.tgz）
    versions=$(echo "$page_content" | grep -oE 'docker-[0-9]+\.[0-9]+\.[0-9]+(-ce)?\.tgz' | sed 's/docker-//g' | sed 's/\.tgz//g' | sort -V | uniq)
    
    if [ -z "$versions" ]; then
        echo "错误: 未找到任何Docker版本"
        exit 1
    fi
    
    echo "可用的Docker版本:"
    echo "=================="
    for version in $versions; do
        echo "  $version"
    done
    echo "=================="
    echo "总共找到 $(echo "$versions" | wc -l) 个版本"
}

# Docker安装函数
install_docker() {
    local version=$1
    
    if [ -z "$version" ]; then
        echo "错误: 请指定要安装的Docker版本"
        return 1
    fi
    
    echo "开始安装Docker版本: $version"
    echo "================================"
    
    # 构建下载URL
    mirrorFile="${mirror}docker-${version}.tgz"
    echo "下载地址: $mirrorFile"
    
    # 检查是否已安装Docker
    if command -v docker >/dev/null 2>&1; then
        current_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-ce)?')
        echo "警告: 检测到已安装的Docker版本: $current_version"
        read -p "是否继续安装新版本? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "安装已取消"
            return 1
        fi
    fi
    
    # 创建临时目录
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 下载Docker二进制文件
    echo "正在下载Docker二进制文件..."
    if ! wget -q --show-progress "$mirrorFile"; then
        echo "错误: 下载失败，请检查网络连接或版本号是否正确"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 解压到/usr/bin/（扁平化解压）
    echo "正在解压Docker二进制文件到/usr/bin/..."
    if ! tar -xzf "docker-${version}.tgz" --strip-components=1 -C /usr/bin/; then
        echo "错误: 解压失败"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 设置执行权限
    chmod +x /usr/bin/docker*
    
    # 清理临时文件
    cd - >/dev/null
    rm -rf "$temp_dir"
    echo "✓ Docker二进制文件安装完成"
    
    # 创建/etc/docker目录
    if [ ! -d "/etc/docker" ]; then
        echo "创建/etc/docker目录..."
        mkdir -p /etc/docker
        echo "✓ /etc/docker目录创建完成"
    fi
    
    # 下载daemon.json配置文件
    if [ ! -f "/etc/docker/daemon.json" ]; then
        echo "下载daemon.json配置文件..."
        if wget -q "$daemonFile" -O /etc/docker/daemon.json; then
            echo "✓ daemon.json配置文件下载完成"
        else
            echo "警告: daemon.json下载失败，将使用默认配置"
        fi
    else
        echo "✓ daemon.json已存在，跳过下载"
    fi
    
    # 备份现有的docker.service文件（如果存在）
    if [ -f "/etc/systemd/system/docker.service" ]; then
        echo "备份现有的docker.service文件..."
        cp /etc/systemd/system/docker.service /etc/systemd/system/docker.service.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 下载docker.service文件
    echo "下载docker.service配置文件..."
    if wget -q "$dockerServiceFile" -O /etc/systemd/system/docker.service; then
        echo "✓ docker.service配置文件下载完成"
    else
        echo "错误: docker.service下载失败"
        return 1
    fi
    
    # 设置执行权限
    chmod +x /etc/systemd/system/docker.service
    
    # 重新加载systemd配置
    echo "重新加载systemd配置..."
    systemctl daemon-reload
    
    # 启动Docker服务
    echo "启动Docker服务..."
    if systemctl start docker; then
        echo "✓ Docker服务启动成功"
    else
        echo "错误: Docker服务启动失败"
        return 1
    fi
    
    # 设置开机自启
    echo "设置Docker开机自启..."
    if systemctl enable docker.service; then
        echo "✓ Docker开机自启设置完成"
    else
        echo $?
        echo "警告: Docker开机自启设置失败"
    fi
    
    # 验证安装
    echo "================================"
    echo "验证Docker安装..."
    if docker -v; then
        echo "🎉 Docker安装完成！"
        echo "================================"
        echo "提示: 如需非root用户使用Docker，请执行："
        echo "  sudo usermod -aG docker \$USER"
        echo "  newgrp docker"
    else
        echo "❌ Docker安装验证失败"
        return 1
    fi
}

# 版本选择函数
select_version() {
    echo "请选择要安装的Docker版本："
    echo "1. 安装最新版本"
    echo "2. 从版本列表中选择"
    echo "3. 手动输入版本号"
    
    read -p "请输入选项 (1-3): " choice
    
    case $choice in
        1)
            # 获取最新版本
            latest_version=$(echo "$versions" | tail -n 1)
            echo "将安装最新版本: $latest_version"
            install_docker "$latest_version"
            ;;
        2)
            # 显示版本列表供选择
            get_docker_versions
            echo ""
            read -p "请输入要安装的版本号: " selected_version
            if echo "$versions" | grep -q "^$selected_version$"; then
                install_docker "$selected_version"
            else
                echo "错误: 版本号不存在"
                return 1
            fi
            ;;
        3)
            # 手动输入版本号
            read -p "请输入Docker版本号 (如: 20.10.17 或 18.06.3-ce): " manual_version
            install_docker "$manual_version"
            ;;
        *)
            echo "无效选项"
            return 1
            ;;
    esac
}

# 主菜单
main_menu() {
    echo "Docker静态安装脚本"
    echo "=================="
    echo "1. 查看可用版本"
    echo "2. 安装Docker"
    echo "3. 退出"
    
    read -p "请选择操作 (1-3): " option
    
    case $option in
        1)
            get_docker_versions
            echo ""
            main_menu
            ;;
        2)
            # 先获取版本列表
            echo "正在获取版本列表..."
            page_content=$(curl -s "$mirror")
            versions=$(echo "$page_content" | grep -oE 'docker-[0-9]+\.[0-9]+\.[0-9]+(-ce)?\.tgz' | sed 's/docker-//g' | sed 's/\.tgz//g' | sort -V | uniq)
            
            if [ -z "$versions" ]; then
                echo "错误: 无法获取版本列表"
                return 1
            fi
            
            select_version
            ;;
        3)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效选项"
            main_menu
            ;;
    esac
}

# 启动主菜单
main_menu