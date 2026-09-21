# Audiobookshelf for TOS 7

[Audiobookshelf](https://github.com/advplyr/audiobookshelf)（自托管有声书/播客服务器）
的 TerraMaster TOS 7 应用中心 deb 封装。不修改上游代码，只做封装层。

## 特性

- **官方构建**：内置上游 2.36.0 官方 apt 仓库的单文件 SEA 构建（Node 运行时 +
  Web 客户端一体，sha256 校验）
- **离线可用**：媒体处理使用 TOS 系统自带的 ffmpeg/ffprobe（Depends 已声明，
  安装即用，包内零预编译二进制，符合商店 V6 审计要求），
  不像官方 deb 首启需要联网下载组件
- **安全默认**：仅监听 `127.0.0.1:13378`（对外一律走 TOS nginx 8181 标准路由），
  专用非特权用户 + systemd 沙箱加固（含个别 TOS 构建的 NNP 兼容自动探测降级）
- **升级路径**：与官方 deb 同包名，官方包用户可直接升级；数据目录
  `/var/lib/audiobookshelf`（`apt remove` 保留，`apt purge` 清除）

## 安装（TOS 7 x86_64）

TOS 桌面 → 应用中心 → 手动安装 → 上传 `audiobookshelf_x86_64.deb`；
或命令行 `apt install ./audiobookshelf_2.36.0-1_amd64.deb`。

安装后：TOS 桌面点图标（新标签页打开 `http://<NAS的IP>:8181/audiobookshelf/`）→
创建管理员账号 → 添加媒体库。

**媒体库权限**：先把 TOS 控制面板 → 共享文件夹中媒体目录的读写权限授予
应用用户 `audiobookshelf`，再在应用里添加该路径。

## 构建

```bash
./build.sh        # fetch → stage → verify → deb
./build.sh info   # 当前配置
```

产物在 `out/`：本地测试用 `audiobookshelf_<版本>_amd64.deb`，
上架资产用 `audiobookshelf_x86_64.deb(.sha256)`。

## 文档

- `AGENTS.md` — 项目宪法（阅读顺序/约束/命令）
- `HANDOFF.md` — 交接清单
- `docs/TASK_STATE.md` — 当前状态与真机验证记录
- `docs/DESIGN_DECISIONS.md` — 架构决策台账（D-001~D-012）
- `docs/CHANGELOG.md` — 版本历史
- `assets/MIGRATION.md` — 官方 deb → 本包迁移指引（随包分发）

## 许可

上游 Audiobookshelf 为 GPL-3.0（`copyright` 随包分发）。
本封装层的构建脚本与资产以 MIT 提供。
