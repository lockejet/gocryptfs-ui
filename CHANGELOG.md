# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/)。

## [0.9.1] - 2026-11-08

**安装 / Install** — 用户级装到 `~/.local/bin`（默认，无需 sudo），系统级加 `--system` 装到 `/usr/local/bin`：

```bash
curl -LsSf https://github.com/lockejet/gocryptfs-ui/releases/latest/download/gocryptfs-ui-install.sh | sh
curl -LsSf https://github.com/lockejet/gocryptfs-ui/releases/latest/download/gocryptfs-ui-install.sh | sh -s -- --system
```

预编译包（x86_64/aarch64 glibc、x86_64 musl）、`source.tar.gz` 与 sha256 校验和见下方 Assets；git clone 与源码编译两种方式见 [README](https://github.com/lockejet/gocryptfs-ui#installation)。

### Bug Fixes
- 从 0.8.x 升级时清理悬空 gocryptfs-cli 符号链接 (install)
- 修复从 0.8.x 升级时安装失败（`cp: not writing through dangling symlink`）：
  旧版 `bin/gocryptfs-cli` 是指向 `lib/gocryptfs-ui/gocryptfs-cli` 的符号链接，
  新版安装器清理旧 `lib/` 后再复制会命中悬空链接。现在复制前先删除旧链接，
  并新增"旧布局升级"回归测试（模拟 0.8 布局 + 悬空链接）。

### Documentation
- Systemd 系统级单元 + Nginx 域名/IP:端口双入口模板 (deploy)

## [0.9.0] - 2026-11-08

### Documentation
- 更新 CHANGELOG


### Features
- 单文件自包含 gocryptfs-cli + 安装元数据迁到 share/<app>/install (cli)

## [0.8.0] - 2026-11-06

### Documentation
- 更新 CHANGELOG

## [0.7.1] - 2026-11-06

### Documentation
- 更新 CHANGELOG

## [0.7.0] - 2026-11-05

### Documentation
- 更新 CHANGELOG

## [0.6.1] - 2026-10-31

### Documentation
- 更新 CHANGELOG

## [0.6.0] - 2026-10-31

### Documentation
- 更新 CHANGELOG

## [0.5.3] - 2026-10-10

### Documentation
- 更新 CHANGELOG

## [0.5.2] - 2026-10-04

### Documentation
- 更新 CHANGELOG

## [0.5.1] - 2026-10-04

### Documentation
- 更新 CHANGELOG

## [0.5.0] - 2026-10-04

### Documentation
- 更新 CHANGELOG
- 更新 CHANGELOG

## [0.4.2] - 2026-10-04

### Documentation
- 更新 CHANGELOG

## [0.4.1] - 2026-10-04

### Documentation
- 更新 CHANGELOG

## [0.4.0] - 2026-10-04

### Documentation
- 更新 CHANGELOG
- 更新 CHANGELOG

## [0.3.0] - 2026-10-04

### Documentation
- 更新 CHANGELOG

## [0.2.2] - 2026-10-04

### Documentation
- 更新 CHANGELOG

## [0.2.1] - 2026-10-03

### Documentation
- 更新 CHANGELOG

## [0.2.0] - 2026-10-03

### Documentation
- 更新 CHANGELOG

## [0.1.2] - 2026-09-30

### Documentation
- 更新 README 与 CHANGELOG 键位说明


### Features
- 换页与换区键位对齐主流 TUI 惯例 (tui)

## [0.1.1] - 2026-09-30

### Documentation
- 更新 README 并生成 CHANGELOG


### Features
- 新增命令行参数解析 (cli)
- 新增统一 JSONL 日志模块 (logger)
- 统一日志格式并新增 log 子命令 (cli)
- 接入参数解析与日志，新增帮助导出和历史过滤 (tui)


### Miscellaneous
- 初始化 cargo-dist


### Build
- 新增版本注入与 cargo-release/cargo-dist 发布流程


### Revert
- 撤回配置文件 git 版本管理
