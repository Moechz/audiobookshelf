# Design decisions

## 1. 上游二进制与分发

### D-001: 复用官方 PPA deb 的单文件 SEA 构建，不做源码构建
**Decision:** 从上游官方 apt 仓库（`https://advplyr.github.io/audiobookshelf-ppa/`）
下载 `audiobookshelf_<ver>_amd64.deb`，提取其中单文件 SEA ELF（~93MB，Node v20 +
Web 客户端 + 全部服务端逻辑打包为单可执行文件）作为本包的唯一上游构件。
**Consequences:**
- 零源码构建、零 Node 依赖管理；上游 GitHub release 本身不带二进制资产
- sha256 pin 在 config.env，防 PPA 索引漂移与供应链替换
- 升级 = 换 ABS_VERSION + 更新 pin + 重跑构建
- SEA 为动态链接（glibc），目标 TOS 7（Ubuntu 22.04 基座）兼容，真机已验证

### D-006: 暂只支持 amd64（x86_64），arm64 显式失败
**Decision:** 构建脚本对 `TARGET_ARCH=arm64` 直接报错退出。
**Consequences:**
- 上游 PPA 截至 2.36.0 只发布 amd64；arm64 需自行从源码构建 SEA（Node pkg 打包
  全量 JS 依赖），成本高且无法复用官方校验链
- TerraMaster 绝大多数主力机型为 x86_64；arm64 需求出现时再立项
- 满足上游发布 arm64 后可低成本跟进（改 fetch URL 即可）

## 2. 运行时伴生二进制（S8 合规关键）

### D-008: ffmpeg/ffprobe/libnusqlite3 三件套随包预置 + unit env 指定路径
**Decision:** 构建期下载 ffmpeg 5.1 / ffprobe 5.1（ffbinaries 官方预构建）与
libnusqlite3 v1.2（上游作者 mikiher 的 release），随包放 `/usr/local/audiobookshelf/bin/`，
systemd unit 里 `Environment=FFMPEG_PATH/FFPROBE_PATH/NUSQLITE3_PATH` 指定路径；
`.so` 旁写 `.ver` 文件（内容 `1.2`）。
**Consequences:**
- 根因（真机实锤，2026-09-17 首装）：SEA 的 BinaryManager 找不到三件套时会
  **在线下载**（ffbinaries.com / GitHub）——违反商店 S8 红线；且下载目标目录
  `/usr/local/.../bin` 在 `ProtectSystem=strict` 下只读（EROFS），安装流程挂起，
  服务进程活着但永不监听（systemd 显示 active，HTTP 拒连）
- 预置后 BinaryManager `Found valid` 三连命中（env 路径优先级最高），零下载、
  零网络依赖，离线 NAS 亦可正常初始化
- 版本约束来自上游 `BinaryManager.validVersions` 硬编码：ffmpeg/ffprobe `5.1.x`、
  libnusqlite3 `1.2.x`（升级 ABS 版本时需复核此约束）
- ffmpeg/ffprobe 为静态链接 ELF，glibc 兼容面最大化
- zip 的 sha256 pin 在 config.env；用户可在 env 文件覆盖路径（换自编译 ffmpeg）

## 3. 打开方式与网络

### D-002: 新标签页（External Open）模式
**Decision:** config.ini 用 `"open_path": true` + `"path": "/audiobookshelf/"`，
不出现 `type` 字段（互斥）。
**Consequences:**
- 零子路径适配成本（ audiobookshelf 全功能 Web 应用，iframe 会受
  `frame-ancestors 'self'` CSP 限制，需要 ALLOW_IFRAME hack）
- 上游 CSP 默认 `frame-ancestors 'self'`——iframe 模式必须改应用行为，不可取
- `allow_open_in_mobile: true`（响应式 Web + 官方移动 App 生态）

### D-003: nginx 前缀保留反代（应用原生 base path 匹配）
**Decision:** `location /audiobookshelf/ { proxy_pass http://127.0.0.1:13378; }`
（proxy_pass 无尾 URI，前缀原样透传）；unit 写死
`Environment=ROUTER_BASE_PATH=/audiobookshelf`。
**Consequences:**
- 上游 v2.x SEA 默认 `ROUTER_BASE_PATH=/audiobookshelf`（index.js
  `?? '/audiobookshelf'`），Next.js 客户端资源、socket.io、RSS/分享链接前缀
  全部天然一致，零重写环路（对比：TOS 官方模板的剥离前缀模式会多一层
  URL 重写往返，行为依赖上游重写中间件）
- Environment= 锁定防上游未来改默认值；env 文件同名变量可覆盖
- 真机验证：`/audiobookshelf/` 200、无尾斜杠 301 → 相对 Location（坑 13 通过）、
  socket.io WebSocket 101、api 鉴权正常
- `absolute_redirect off` + `Host $http_host`（坑 13/14 标配）

### D-004: 端口 13378 仅回环（与官方 deb 默认一致）
**Decision:** `--port 13378 --host 127.0.0.1` 写死 ExecStart。
**Consequences:**
- 与官方 deb 默认端口一致（升级路径平滑）；在官方推荐段 8000-19999 内
- 端口/host 不进 env 文件（navidrome 模式：env 误删/漏配不致端口外泄）
- 用户确需改端口：编辑 `/etc/systemd/system/audiobookshelf.service` 副本后
  daemon-reload + restart（unit 内有注释指引）

## 4. 包身份与数据

### D-005: 包名 = appid = `audiobookshelf`（同包名天然升级路径）
**Decision:** dpkg Package 名用 `audiobookshelf`（与官方 deb 完全同名），
不加 Conflicts/Replaces（同包名不能 Conflicts 自身，也无需）。
**Consequences:**
- navidrome 先例（坑 10 变体）：官方 deb 用户可直接升级到本包，dpkg 自动
  清理旧版文件（除 conffile `/etc/default/audiobookshelf`，本包不读它，无害残留）
- 布局差异（官方 `/usr/share/audiobookshelf/{config,metadata}` vs 本包
  `/var/lib/audiobookshelf/`）：postinst 检测旧布局打印迁移提示，
  **绝不自动搬数据**（MIGRATION.md 随包提供手动步骤）
- 显示名用 "Audiobookshelf Server"（坑 12 防商店撞名；真机 grep 已确认无撞名）

### D-010: 数据目录 /var/lib/audiobookshelf/{config,metadata}
**Decision:** `--config /var/lib/audiobookshelf/config --metadata /var/lib/audiobookshelf/metadata`
写死 ExecStart；`apt remove` 保留、`apt purge` 清除。
**Consequences:**
- 媒体库本身在用户共享文件夹（TOS 模型：共享文件夹权限 UI 把目录授权给
  应用用户 `audiobookshelf`），postinst 输出与 lang 均有指引
- purge 同时清包清单外派生文件（webui 解压物、首装 env）——dpkg 不删非空目录

## 5. 兼容性与合规

### D-007: 23 语超集 lang 文件
**Decision:** 真机 14 语 + 官方英文文档口径 9 语（ar-sa/cs-cz/he-il/id-id/nb-no/
nl-nl/sv-se/th-th/vi-vn）全量提供；en/zh-cn/zh-hk/ja 认真翻译，其余填英文。
**Consequences:**
- 同时覆盖两个官方口径（hermesagent/Rsync Backup 先例，随包真机验证过）
- 未翻译节点填英文未 observed 副作用；送审侧如反馈冗余再裁剪

### D-009: NNP 探测 + 最小降级 drop-in（坑 23）
**Decision:** postinst 用 `timeout 15 systemd-run --wait --collect -p
NoNewPrivileges=true /bin/true` 探测；仅失败时安装
`80-audiobookshelf-exec-compat.conf`（NNP=false + RestrictSUIDSGID=false）；
探测通过时自动删降级文件；`AUDIOBOOKSHELF_EXEC_COMPAT=force|off` 环境变量钩子。
**Consequences:**
- 个别 TOS 构建在 NNP 下拒绝一切 execve（netcheck 三真机实锤）；探测降级
  保证该类机器可用，正常机器保留全部加固
- postrm purge 只删本包已知 drop-in 文件名，不动管理员自定义（坑 27）

### D-011: 隐私政策三处可达（坑 21/45，2.36.0-2 整改）
**Decision:** 隐私政策以 `privacy-policy.html` 进 webui.bz2 与应用目录，
**并加 nginx 精确路由**
`location = /audiobookshelf/privacy-policy.html { alias /usr/local/audiobookshelf/privacy-policy.html; }`
（精确匹配优先于前缀反代，静态直出）；商店送审表单再填公开仓库政策页 URL，
三处可达。
**Consequences:**
- External Open 模式下应用内无入口的结构性缺口由 nginx 路由弥补：
  `/audiobookshelf/privacy-policy.html` 任何用户/审核员可直接访问（真机 200）
- 与 alist 首审 C3 驳回整改同款；提审表单的 URL 仍需上架流程补录

## 6. 版本与发布

### D-012: 版本号 `<上游>-<迭代>`（如 2.36.0-1），三处一致 + Release tag 同名
**Decision:** config.ini version / DEBIAN/control Version / .lang version 均为
完整版本；上架 Release tag = `v<完整版本>`；迭代号永不零填充。
**Consequences:**
- 未上架前同版本可重建 deb 原地替换资产（坑 19）
- 上架后每次变更必须递增迭代号新发 release

## 7. 商店合规整改（2.36.0-2，对应指南 2026-09-19 版新坑）

### D-013: ffmpeg/ffprobe 改走 TOS 系统包（V6 一票否决项整改）
**Decision:** 不再随包分发 ffmpeg/ffprobe/libnusqlite3 预编译 ELF；control
`Depends: ffmpeg`（Ubuntu 22.04 universe 4.4.x，真机预装）；systemd unit 设
`FFMPEG_PATH=/usr/bin/ffmpeg`、`FFPROBE_PATH=/usr/bin/ffprobe`、
`SKIP_BINARIES_CHECK=1`（跳过上游 BinaryManager 的 5.1 版本白名单，否则会
触发在线下载——S8）；libnusqlite3 为上游可选组件，不设 NUSQLITE3_PATH
即不加载，unicode 排序退化为默认（可接受）。
**Consequences:**
- 包内仅剩 SEA 一个 ELF（V6 门禁 verify 断言：额外 ELF 计数必须 0）；
  包体积 61MB → 22MB，装机占用 -157MB
- 系统 ffmpeg 4.4 vs 上游白名单 5.1：abs 的转码/元数据调用均为通用参数，
  社区 Debian 用户长期跑 4.x；真机升级回归全绿，但完整转码功能待媒体库
  实测（TASK_STATE 待办）
- SKIP 模式下 BinaryManager 不做存在性校验，极端机器缺 ffmpeg 时转码才报错
  ——postinst 有存在性探测提示（不在线装，S8）

### D-014: 署名与 official 字段（2026-09-21 用户决策，当日修订）
**Decision：**
- `publisher`（config.ini）= **Moechz**——往后所有 TOS 封装（deb+docker）同此规则；
  control `Maintainer` 同为 Moechz；Description 尾注保留 "Upstream author: advplyr"
- `.lang` 23 节点 `auth` = **advplyr**（上游作者，用户指定保留，**勿动**）
- `official` 填 TerraMaster 论坛帖
  `https://forum.terra-master.com/en/viewtopic.php?t=10611`
  （⚠️ 已实测：脚本 GET 被 Cloudflare 拦 403，指南坑 30a 的 netcheck 先例
  因 official 指论坛帖被 V6 驳；若送审被驳，退路 = official 改公开仓库
  + 论坛帖移入 help 字段，各一行改动）
**Consequences:**
- publisher 与 auth 分工：publisher=打包者署名、auth=上游开发者署名；
  2026-09-21 曾误把 auth 一起改成 Moechz，已被用户纠正——教训：
  用户未点名的字段不擅自连带修改

### D-015: SEA 二进制的 V6 可审计链（CI 自建路线，待建仓实施）
**Decision:** 指南 2026-09 实锤：即使上游官方发布的二进制直接打包也会被
V6 驳（sftpgo/beszel 先例）；唯一出路 = 公开仓库 + CI 从源码复刻自建。
配方：锁上游 tag 源码 + Node 20.11.1 + `pkg -t node20-linux-x64`
（复刻上游 build/linuxpackager）+ 两次构建哈希互证；pkg-fetch 拉取的
node fetch binary 记录 sha256 进 PROVENANCE（官方源+锁哈希，弱一环）。
**Consequences:**
- 2.36.0-2 仍是官方 PPA 预编译 SEA（compat 模式，仅供本地/真机功能验证），
  **提交商店前必须切 source 模式**（fetch CI 自建产物）
- CI 配方文件（.github/workflows/release.yml + repro 材料）已入库待跑
