# PROVENANCE — 包内文件来源审计表（V6 材料）

> 本表覆盖 deb 包内每个非文本资产/二进制的来源与校验方式。
> 媒体处理用的 ffmpeg/ffprobe 来自 TOS 基座系统包（`Depends: ffmpeg`，
> Ubuntu 22.04 universe），**不随包分发任何预编译 ffmpeg ELF**。

## 审计表

| 包内路径 | 类型 | 来源 | 校验 |
|---|---|---|---|
| `bin/audiobookshelf` | ELF（Node SEA 单文件） | 见下「SEA 来源」 | sha256（config.env pin） |
| `config.ini` / `.lang` / `nginx/*.conf` / `init.d/*.service` / `webui.bz2` / `*.env.example` / `MIGRATION.md` | 文本 | 本仓库（明文可审计） | 构建期 LF/BOM 清洗 + verify 断言 |
| `images/icons/audiobookshelf.svg` | SVG 文本 | 上游 `icon.svg`（raw，v tag） | verify：XML 可解析 + viewBox + path 截断检测 |
| `/usr/share/doc/audiobookshelf/copyright` | 文本 | 上游 LICENSE（raw，v tag） | 随源码 tag |

## SEA 来源（两条路线）

| 模式 | 来源 | 状态 |
|---|---|---|
| `compat`（本地/真机功能验证） | 上游官方 PPA deb（advplyr.github.io/audiobookshelf-ppa），sha256 pin 于 config.env；上游构建配方（build/linuxpackager）与源码全公开 | 2.36.0-2 当前默认 |
| `source`（**商店提交必须**） | 本仓库 GitHub Actions `build-sea` workflow 从上游 tag 源码自建：Node 20.11.1 + `pkg -t node20-linux-x64`（复刻上游 build/linuxpackager 逐字命令），连续两次构建哈希互证；pkg-fetch 的 node fetch binary（vercel/pkg-fetch 官方 Release）sha256 记录于 workflow 日志 | 待建仓首跑（D-015） |

## 版本记录

| 版本 | SEA 来源 | SEA sha256（前 16 位） |
|---|---|---|
| 2.36.0-1 | 上游 PPA deb | 51035247e0e3a41e（随包，现已过时） |
| 2.36.0-2 | 上游 PPA deb（compat） | 同上 |
