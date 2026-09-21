# Changelog

## 2.36.0-2 — 2026-09-19

### Changed（商店合规整改，对应指南 2026-09-19 新坑 30a/31-49）
- **V6 整改（一票否决项）**：不再随包分发 ffmpeg/ffprobe/libnusqlite3
  预编译 ELF——改用 TOS 系统包（`Depends: ffmpeg`）+ unit 设
  `FFMPEG_PATH/FFPROBE_PATH=/usr/bin/*` + `SKIP_BINARIES_CHECK=1`；
  包内仅剩 SEA 一个 ELF（verify 新增 V6 硬门禁：额外 ELF 计数必须 0）；
  包体积 61MB → 22MB（真机升级自动释放 157MB）
- **C3 整改**：隐私政策新增 nginx 精确路由
  `location = /audiobookshelf/privacy-policy.html`（静态直出，真机 200）
- **署名（项目决策）**：publisher = Moechz（所有 TOS 封装规则）；
  lang auth = advplyr（上游作者，用户指定保留）；
  deb Maintainer = Moechz；Description 尾注保留 Upstream author: advplyr；
  official 改填 TerraMaster 论坛帖（已实测脚本 GET 403，退路见 D-014）
- **S11 整改**：webui.bz2 改用 python tarfile 重打（uid/gid=0、
  uname/gname=root、mtime=0），不再用 macOS bsdtar（uid 501 污染）
- 本地测试包改名 `audiobookshelf_2.36.0-2_x86_64.deb`（避 amd64 字样：
  App Center 手动安装页对 `*amd64*.deb` 报解析失败，坑 30 note）

### Fixed
- build.sh 四处 `管道 | grep -q` 的 SIGPIPE 假失败风险改计数式/case 式（坑 33）

### Added（verify 新断言）
- lang 全文 beta/alpha/rc 门禁（坑 41 V11）
- config.ini path 路由格式门禁 + official 字段存在性（坑 37/30a）
- 图标 SVG XML 完整性断言（坑 47）
- webui.bz2 归档属主/mtime 断言（坑 46）
- SEA 加壳检测（no section header，坑 43）
- unit SKIP_BINARIES_CHECK/系统 ffmpeg 路径断言（S8 联防）

## 2.36.0-1 — 2026-09-17

### Added
- 首个 TOS 7 应用中心封装版本：基于 Audiobookshelf 上游 2.36.0（官方 PPA 的
  单文件 SEA 构建，sha256 校验）
- ffmpeg 5.1 / ffprobe 5.1 / libnusqlite3 v1.2 三件套随包预置：安装即用、
  无需联网，离线 NAS 亦可正常初始化（上游 SEA 默认会在线下载这三个组件）
- Web UI 经 TOS 标准路由 `/audiobookshelf/` 新标签页打开；后端仅监听
  127.0.0.1:13378，不对外多开任何端口
- 23 语言应用描述（中/繁中/英/日全译，其余英文兜底）
- 双语隐私政策随包（`/usr/local/audiobookshelf/webui 解压目录/privacy-policy.html`）
- 官方 deb → 本包的手动迁移指引（`/usr/local/audiobookshelf/MIGRATION.md`）；
  同包名升级自动生效，数据不迁移不删除
- systemd 沙箱加固（NoNewPrivileges/ProtectSystem 等）+ 个别 TOS 构建的
  NNP 兼容自动探测降级
- `apt remove` 保留用户数据（/var/lib/audiobookshelf），`apt purge` 全清
