# Docker 静态安装脚本

一个用于在 Ubuntu/Debian 系统上安装 Docker 的纯静态安装脚本，不依赖系统包管理器安装 Docker。

## ✨ 功能特点

### 🚀 绿色安装
- **纯静态二进制** - 直接下载 Docker 官方静态编译版本
- **无包管理依赖** - 不通过 apt 等包管理器安装 Docker
- **完全可控** - 手动管理 Docker 版本，避免系统更新冲突
- **快速部署** - 跳过复杂的仓库配置和依赖解析
- **支持架构**: x86_64 和 aarch64 (ARM64)

## 🚀 快速开始

### 方法一：一键安装 (推荐)
```bash
curl -sL https://raw.githubusercontent.com/ellermister/docker-static-install/main/docker | bash
```

### 方法二：下载脚本安装
```bash
wget -O install.sh https://github.com/ellermister/docker-static-install/raw/main/install.sh
chmod +x install.sh
./install.sh
```

### 方法三：克隆仓库
```bash
git clone https://github.com/ellermister/docker-static-install.git
cd docker-static-install
./install.sh
```

## 📖 使用说明

运行脚本后，会出现交互式菜单：

```
Docker静态安装脚本
==================
1. 查看可用版本
2. 安装Docker
3. 退出
```

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！
