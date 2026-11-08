### Bug Fixes

- 修复从 0.8.x 升级时安装失败（`cp: not writing through dangling symlink`）：
  旧版 `bin/gocryptfs-cli` 是指向 `lib/gocryptfs-ui/gocryptfs-cli` 的符号链接，
  新版安装器清理旧 `lib/` 后再复制会命中悬空链接。现在复制前先删除旧链接，
  并新增"旧布局升级"回归测试（模拟 0.8 布局 + 悬空链接）。
