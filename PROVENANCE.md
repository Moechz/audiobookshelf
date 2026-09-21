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
| `compat`（本地/真机功能验证） | 上游官方 PPA deb（advplyr.github.io/audiobookshelf-ppa），sha256 pin 于 config.env；上游构建配方（build/linuxpackager）与源码全公开 | 已被 source 取代 |
| `source`（**商店提交采用**） | 本仓库 GitHub Actions `build-sea` workflow 从上游 tag 源码自建：Node 工具链 20.11.1（setup-node）+ @yao-pkg/pkg@5.16.1（pkg-fetch 3.6.5，内嵌运行时 Node 20.18.0；上游 linuxpackager 未锁 pkg 版本，vercel/pkg 不支持 node20 target，故用社区 fork），命令序列复刻上游 linuxpackager；源码归档与产物 sha256 双层校验 | **当前生效**（v2.36.0-2 起） |

## 版本记录

| 版本 | SEA 来源 | SEA sha256（前 16 位） |
|---|---|---|
| 2.36.0-1 | 上游 PPA deb（Node 20.11.1） | 51035247e0e3a41e（随包，已过时） |
| 2.36.0-2 | **本仓 CI 自建**（`build-v2.36.0` Release：上游 tag 源归档 c38c2927… + @yao-pkg/pkg@5.16.1 + Node 20.18.0 fetch binary；两次构建哈希互证 differs——pkg 产物内嵌时间戳无法位级一致，已如实记录） | 30b6b30274436204 |
