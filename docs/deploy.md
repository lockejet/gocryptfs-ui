# 部署指南：systemd + Nginx 双入口（域名 / 私网 IP:端口）

目标：同一套 gocryptfs-web 服务，既能通过**私网 IP + 端口**访问
（如 `https://192.168.8.231:44332`），也能通过**域名**访问
（如 `https://gocryptfs.example.com`）；后端进程只监听 `127.0.0.1:30032`，
由 Nginx 终止 TLS 并反代。应用侧只开 `--trust-proxy`，**不固定
`--public-url`**，这样两种入口的登录 cookie（`Secure`）、扫码登录链接、
CSRF 同源校验、限流/审计客户端 IP 都能自动正确。

> 同一台机器上的 rbackup-ui 用完全相同的骨架，端口表：
>
> | 应用 | 后端监听 | HTTP 入口 | HTTPS 入口 | systemd 单元 |
> |---|---|---|---|---|
> | gocryptfs-ui | `127.0.0.1:30032` | `8032` | `44332` | `gocryptfs-web.service` |
> | rbackup-ui | `127.0.0.1:30031` | `8031` | `44331` | `rbackup-web.service` |
>
> 两个应用各自独立配置，凭据互不共享。

## 1. 安装

```sh
curl -fsSL https://github.com/lockejet/gocryptfs-ui/releases/latest/download/gocryptfs-ui-install.sh | bash
# 或从源码：make install
```

安装后 `~/.local/bin/` 下是三个真实文件：`gocryptfs-tui`、`gocryptfs-web`、
`gocryptfs-cli`（单文件 bash 后端；TUI/Web 二进制也会内嵌一份，运行期释放到
`~/.local/share/gocryptfs-ui/backend/`）。

## 2. 准备凭据（可选：token 默认自动生成）

```sh
mkdir -p ~/.config/gocryptfs-ui && chmod 700 ~/.config/gocryptfs-ui

# token 文件不存在时，首次启动会自动生成并打印一次明文 token；
# 也可以提前创建（推荐，避免明文进 journal）：

openssl rand -base64 32 > ~/.config/gocryptfs-ui/web.token

# 用户名密码（可选，日常登录推荐）
~/.local/bin/gocryptfs-web user add admin     # 交互输入密码，argon2id 存储
~/.local/bin/gocryptfs-web user list

# 2FA（可选，Web「安全」页扫码绑定 TOTP；默认关闭）
chmod 600 ~/.config/gocryptfs-ui/web.token ~/.config/gocryptfs-ui/web.auth 2>/dev/null || true
```

## 3. systemd（单一进程来源）

仓库自带模板 `contrib/systemd/gocryptfs-web.service`：

```sh
cd /path/to/gocryptfs-ui
sed -e "s|__USER__|$USER|g" -e "s|__GROUP__|$(id -gn)|g" \
    -e "s|__HOME__|$HOME|g" contrib/systemd/gocryptfs-web.service \
  | sudo tee /etc/systemd/system/gocryptfs-web.service

sudo systemctl daemon-reload
sudo systemctl enable --now gocryptfs-web
systemctl status gocryptfs-web --no-pager
```

清理旧来源（如有），避免抢端口：

```sh
# 旧用户级单元（早期文档推荐过）
systemctl --user disable --now gocryptfs-web 2>/dev/null || true
rm -f ~/.config/systemd/user/gocryptfs-web.service
systemctl --user daemon-reload 2>/dev/null || true

# 手动进程
pgrep -af gocryptfs-web || true
```

确认只有一个进程在监听 30032：`ss -ltnp | grep 30032`。

> **重要**：gocryptfs 的挂载/卸载必须发生在 host mount namespace 中。
> 不要给本单元加 `PrivateTmp` / `ProtectSystem` / `ProtectHome` 等会创建私有
> mount namespace 的选项，也不要开 `NoNewPrivileges` / `RestrictSUIDSGID`
> （会禁用 fusermount 的 setuid）。模板中已显式关闭。

## 4. Nginx（双入口）

模板：`contrib/nginx/gocryptfs-ip.conf`（IP:端口，HTTP 301 → HTTPS）与
`contrib/nginx/gocryptfs-domain.conf`（域名 443）。

```sh
cd /path/to/gocryptfs-ui

sed -e 's|__LISTEN_IP__|127.0.0.1|g' \
    -e 's|__CERT__|/etc/nginx/ssl/example.crt|g' \
    -e 's|__KEY__|/etc/nginx/ssl/example.key|g' \
    contrib/nginx/gocryptfs-ip.conf | sudo tee /etc/nginx/sites-available/gocryptfs.conf

sed -e 's|__DOMAIN__|gocryptfs.example.com|g' \
    -e 's|__CERT__|/etc/letsencrypt/live/gocryptfs.example.com/fullchain.pem|g' \
    -e 's|__KEY__|/etc/letsencrypt/live/gocryptfs.example.com/privkey.pem|g' \
    contrib/nginx/gocryptfs-domain.conf | sudo tee /etc/nginx/sites-available/gocryptfs-domain.conf

sudo ln -sf /etc/nginx/sites-available/gocryptfs.conf /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/gocryptfs-domain.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

要点：反代必须**覆盖** `X-Forwarded-Proto/Host/For`（模板已含），应用必须带
`--trust-proxy`；SSE 需要 `proxy_buffering off` 与长超时（模板已含）。

## 5. 验证清单

```sh
curl -fsS http://127.0.0.1:30032/healthz && echo OK
curl -kfsS https://192.168.8.231:44332/healthz && echo OK
curl -fsS https://gocryptfs.example.com/healthz && echo OK
curl -sI http://192.168.8.231:8032/ | head -1     # 应 301
```

浏览器逐项确认：

1. 两个入口都能登录；cookie `gfs_session` 带 `Secure; HttpOnly; SameSite=Strict`；
2. 两个入口的「手机登录」二维码链接分别形如 `https://域名/#t=...` 与
   `https://IP:44332/#t=...`（不应出现 `http://` 或 `:80`）；
3. `/api/meta` 中 `trust_proxy` 为 `true`，`public_url` 为空（双入口自适应）；
4. 挂载/卸载卷正常（验证没有 mount namespace 沙箱破坏 fusermount）；
5. 限流/审计日志中的客户端 IP 为真实 IP。

## 6. 与 rbackup-ui 对齐

rbackup-ui 仓库的 `contrib/systemd/rbackup-web.service` 与
`contrib/nginx/rbackup-*.conf` 是同一套模板（端口 30031/8031/44331），
ExecStart 加 `--web-trust-proxy` 即可。两边差异只在参数名
（`--trust-proxy` vs `--web-trust-proxy`）与凭据文件位置
（各自 `~/.config/<app>/`）；域名/IP 双入口的配置方式完全一致。

## 7. 常见问题

| 现象 | 排查 |
|---|---|
| 502 Bad Gateway | 服务没起 / 端口不符：`systemctl status gocryptfs-web`、`ss -ltnp \| grep 30032` |
| 登录后立刻掉线 | 反代未设 `X-Forwarded-Proto: https` 或应用未开 `--trust-proxy`，cookie 没有 `Secure` 被丢弃；或 Origin/Host 不一致导致 403 |
| 扫码链接是 `http://` 或 `host:80` | 同上：未信任代理头（`--trust-proxy` + 代理覆盖 `X-Forwarded-Proto/Host`） |
| 挂载/卸载失败（EPERM） | 单元带了 mount-namespace 沙箱或 NoNewPrivileges，见第 3 节 |
| SSE 日志卡住 | Nginx 未关缓冲：`proxy_buffering off; proxy_read_timeout 3600s;` |
| 端口被占用 | 旧用户级单元/手动进程残留，见第 3 节清理 |
