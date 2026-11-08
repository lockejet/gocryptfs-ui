# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/)。

## [0.9.0] - 2026-11-08

**安装 / Install** — 用户级装到 `~/.local/bin`（默认，无需 sudo），系统级加 `--system` 装到 `/usr/local/bin`：

```bash
curl -LsSf https://github.com/lockejet/gocryptfs-ui/releases/latest/download/gocryptfs-ui-install.sh | sh
curl -LsSf https://github.com/lockejet/gocryptfs-ui/releases/latest/download/gocryptfs-ui-install.sh | sh -s -- --system
```

预编译包（x86_64/aarch64 glibc、x86_64 musl）、`source.tar.gz` 与 sha256 校验和见下方 Assets；git clone 与源码编译两种方式见 [README](https://github.com/lockejet/gocryptfs-ui#installation)。

### Features
- 单文件自包含 gocryptfs-cli + 安装元数据迁到 share/<app>/install (cli)
- 独立 CLI 改为**单文件自包含**：`gocryptfs-cli` 由 i18n + lib + 主脚本拼接生成（`shell/gocryptfs-cli.bundle`），
  直接装进 `<prefix>/bin`，不再依赖 `lib/` 目录与符号链接；`--link-cli` / `--no-link-cli` 变为兼容 no-op
- 安装元数据从 `<prefix>/lib/gocryptfs-ui/` 迁到 `<prefix>/share/gocryptfs-ui/install/`
  （`VERSION`、`INSTALLED.json`、`INSTALLED.files`）；卸载只删 `install/`，保留运行期 `backend/` 等数据
- `gocryptfs-tui --print-paths` 的 Backend 行会显示实际解析到的 CLI（内嵌/外部）路径

### Bug Fixes
- 升级安装时清理 ≤0.8 的旧 `lib/gocryptfs-ui/` 布局，避免残留的多文件后端被误用
- 单文件 CLI 直接执行时不再误触发 lib 的"自索引"分支（`GFS_BUNDLED` 守卫）

### Build
- 新增 `tools/bundle-cli.sh` 与 `make cli-bundle` / `make cli-bundle-check`；`make check` 会校验提交的 bundle 是最新的

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
