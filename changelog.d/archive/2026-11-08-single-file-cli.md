### Features
- 独立 CLI 改为**单文件自包含**：`gocryptfs-cli` 由 i18n + lib + 主脚本拼接生成（`shell/gocryptfs-cli.bundle`），
  直接装进 `<prefix>/bin`，不再依赖 `lib/` 目录与符号链接；`--link-cli` / `--no-link-cli` 变为兼容 no-op
- 安装元数据从 `<prefix>/lib/gocryptfs-ui/` 迁到 `<prefix>/share/gocryptfs-ui/install/`
  （`VERSION`、`INSTALLED.json`、`INSTALLED.files`）；卸载只删 `install/`，保留运行期 `backend/` 等数据
- `gocryptfs-tui --print-paths` 的 Backend 行会显示实际解析到的 CLI（内嵌/外部）路径

### Build
- 新增 `tools/bundle-cli.sh` 与 `make cli-bundle` / `make cli-bundle-check`；`make check` 会校验提交的 bundle 是最新的

### Bug Fixes
- 升级安装时清理 ≤0.8 的旧 `lib/gocryptfs-ui/` 布局，避免残留的多文件后端被误用
- 单文件 CLI 直接执行时不再误触发 lib 的"自索引"分支（`GFS_BUNDLED` 守卫）
