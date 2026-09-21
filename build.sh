#!/usr/bin/env bash
# ============================================================
# build.sh - 在 macOS / Linux 上把 Audiobookshelf 打包成
# TOS 7 应用中心规范的 deb 包（WebUI External Open / 新标签页模式）
#
# 规范依据: https://help.terra-master.com/developer/development-docs/
#   - Deb Development Specification（目录结构/config.ini/nginx/systemd/生命周期）
#   - Package Specification（版本号三处一致、资产命名）
#
# 上游形态: 官方 apt 仓库（GitHub Pages PPA）的单文件 ELF
#   （Node.js SEA：内置运行时 + Web 客户端 + ffmpeg，~93MB）
#   ⚠️ 上游仅发布 amd64；arm64 需自行构建 SEA（见 DESIGN_DECISIONS D-006）
#
# 产物（out/）:
#   audiobookshelf_<版本>_<平台>.deb     完整版本名 deb（本地安装/App Center
#                                         手动安装页测试用；文件名用 TOS 平台
#                                         名 x86_64 —— 避 amd64 字样，
#                                         App Center 手动安装页对 *amd64*.deb
#                                         会报"解析失败"）
#   audiobookshelf_<platform>.deb         Release 资产名 deb（上架上传用）
#   audiobookshelf_<platform>.deb.sha256  上架要求的校验文件
#
# 阶段: fetch → stage → verify → deb
# ============================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# 允许命令行覆盖：BUILD_MODE=source ./build.sh ...（env 优先于 config.env）
_USER_BUILD_MODE="${BUILD_MODE:-}"
# shellcheck source=config.env
. "$SCRIPT_DIR/config.env"
[ -n "$_USER_BUILD_MODE" ] && BUILD_MODE="$_USER_BUILD_MODE"

BUILD_DIR="$SCRIPT_DIR/build"
DL_DIR="$BUILD_DIR/downloads"
STAGE_DIR="$BUILD_DIR/pkgroot"
OUT_DIR="$SCRIPT_DIR/out"
ASSETS_DIR="$SCRIPT_DIR/assets"

# 完整版本 = 上游版本-打包迭代号（如 2.36.0-1）
# 三处必须一致：config.ini / DEBIAN/control / .lang
VERSION_FULL="${ABS_VERSION}-${PKG_RELEASE}"

# ---------------- 目标平台（TOS / NAS 侧） ----------------
case "$TARGET_ARCH" in
  amd64)
    TOS_PLATFORM="x86_64"
    ELF_ARCH="x86-64"
    ;;
  arm64)
    # 上游 PPA 无 arm64 单文件二进制（截至 2.36.0），构建 arm64 包必错——
    # 显式失败而非静默产出坏包（坑 28 的教训：错架构二进制混入）
    echo "错误: 上游官方 PPA 未提供 arm64 构建，本包暂只支持 amd64。" >&2
    echo "      如需 arm64：需从源码构建 SEA 单文件（npm run build + 海量依赖），" >&2
    echo "      参见 DESIGN_DECISIONS.md D-006。" >&2
    exit 1
    ;;
  *)
    echo "错误: 未知 TARGET_ARCH=$TARGET_ARCH（支持 amd64）" >&2
    exit 1
    ;;
esac

UPSTREAM_DEB="audiobookshelf_${ABS_VERSION}_amd64.deb"
UPSTREAM_URL="https://advplyr.github.io/audiobookshelf-ppa/${UPSTREAM_DEB}"
SEA_SOURCE_FILE="audiobookshelf-sea-x86_64"
LICENSE_FILE="LICENSE"
# 本地测试包名用 TOS 平台名（坑 30 note：App Center 手动安装页对
# 含 amd64 的文件名报解析失败；deb 内 Architecture 字段仍写 amd64）
DEB_FILE="$OUT_DIR/${APP_ID}_${VERSION_FULL}_${TOS_PLATFORM}.deb"
STORE_DEB="$OUT_DIR/${APP_ID}_${TOS_PLATFORM}.deb"       # Release 资产命名（无版本）

MAINTAINER_FULL="$MAINTAINER_NAME <$MAINTAINER_EMAIL>"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m警告:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

fetch() { # fetch <url> <dest-file>（多次重试 + 断点续传）
  local url=$1 dest=$2 attempt=0
  if [ -s "$dest" ]; then
    log "已缓存: $(basename "$dest")"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  log "下载: $(basename "$dest")"
  while [ $attempt -lt 8 ]; do
    attempt=$((attempt + 1))
    if curl -fL --retry 5 --retry-delay 3 --retry-all-errors \
         --connect-timeout 30 -C - -o "$dest.part" "$url"; then
      mv "$dest.part" "$dest"
      return 0
    fi
    rm -f "$dest.part"  # 部分服务器不支持续传时从头再来
    warn "下载失败(第 $attempt 次): $(basename "$dest")，10 秒后重试..."
    sleep 10
  done
  die "下载失败: $url"
}

sha256_of() { # sha256_of <file> -> 64 位哈希（macOS/Linux 兼容）
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

normalize_text() { # 规范要求：文本文件 LF 行尾 + UTF-8 无 BOM（构建时统一清洗）
  python3 - "$@" <<'PYEOF'
import sys
for p in sys.argv[1:]:
    with open(p, 'rb') as f:
        data = f.read()
    if data.startswith(b'\xef\xbb\xbf'):
        data = data[3:]
    data = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    with open(p, 'wb') as f:
        f.write(data)
PYEOF
}

# ============================================================
# 阶段: fetch
# ============================================================
stage_fetch() {
  mkdir -p "$DL_DIR"

  if [ "${BUILD_MODE:-compat}" = "source" ]; then
    # source 模式（商店提交必须，V6/D-015）：SEA 来自本仓库 CI 自建产物
    # （.github/workflows/build-sea.yml 从上游 tag 源码复刻 linuxpackager）
    [ -n "${SEA_SOURCE_SHA256:-}" ] \
      || die "BUILD_MODE=source 需要 config.env 里配置 SEA_SOURCE_SHA256（先跑 CI，把 Release 产物的 sha256 回填）"
    case "$SEA_SOURCE_URL" in *__OWNER__*|*__REPO__*) \
      die "SEA_SOURCE_URL 还是占位符，建仓后按实际 owner/repo 修改 config.env" ;; esac
    fetch "$SEA_SOURCE_URL" "$DL_DIR/$SEA_SOURCE_FILE"
    local got
    got=$(sha256_of "$DL_DIR/$SEA_SOURCE_FILE")
    [ "$got" = "$SEA_SOURCE_SHA256" ] \
      || die "sha256 不匹配: $SEA_SOURCE_FILE（want=$SEA_SOURCE_SHA256 got=$got）"
    log "  ok: $SEA_SOURCE_FILE（source 模式，CI 自建）"
  else
    # compat 模式（本地/真机功能验证）：官方 PPA deb 提取 SEA
    fetch "$UPSTREAM_URL" "$DL_DIR/$UPSTREAM_DEB"
  fi

  # 上游 LICENSE（进 /usr/share/doc/audiobookshelf/copyright）
  fetch "https://raw.githubusercontent.com/advplyr/audiobookshelf/v${ABS_VERSION}/LICENSE" \
        "$DL_DIR/$LICENSE_FILE"

  # sha256 校验（全部 pin 在 config.env，防索引漂移/供应链替换）
  log "校验 sha256..."
  local got
  for entry in "$UPSTREAM_DEB:$UPSTREAM_DEB_SHA256" \
               "$LICENSE_FILE:SKIP" \
               "$SEA_SOURCE_FILE:${SEA_SOURCE_SHA256:-SKIP}"; do
    local fname="${entry%%:*}" want="${entry#*:}"
    [ "$want" = "SKIP" ] && continue
    [ -e "$DL_DIR/$fname" ] || continue
    got=$(sha256_of "$DL_DIR/$fname")
    [ "$got" = "$want" ] \
      || die "sha256 不匹配: $fname（want=$want got=$got）\n  若上游确实重发了同版本资产，请核实后更新 config.env"
    log "  ok: $fname"
  done
}

# ============================================================
# 阶段: stage —— 组装 deb 文件系统树（官方规范布局）
# ============================================================
stage_stage() {
  [ -s "$DL_DIR/$UPSTREAM_DEB" ] || die "缺少 $UPSTREAM_DEB，请先运行: ./build.sh fetch"

  local APP="$STAGE_DIR/usr/local/$APP_ID"
  log "组装文件系统树: $STAGE_DIR（/usr/local/$APP_ID 规范布局）"
  rm -rf "$STAGE_DIR"
  mkdir -p "$APP/bin"
  mkdir -p "$APP/images/icons"
  mkdir -p "$APP/nginx"
  mkdir -p "$APP/init.d"
  mkdir -p "$STAGE_DIR/usr/share/doc/$APP_ID"

  # 二进制：SEA 单文件（Node 运行时+客户端一体）
  # compat 模式：从官方 deb 提取（macOS 无 dpkg：ar 解 ar 归档 + tar 解
  # data.tar.xz，兼容 bsdtar/GNU tar）；source 模式：直接取 CI 自建产物
  log "  + bin/audiobookshelf（SEA 单文件，上游 $ABS_VERSION，${BUILD_MODE:-compat} 模式）"
  if [ "${BUILD_MODE:-compat}" = "source" ]; then
    [ -s "$DL_DIR/$SEA_SOURCE_FILE" ] \
      || die "缺少 $SEA_SOURCE_FILE，请先运行: ./build.sh fetch"
    install -m 0755 "$DL_DIR/$SEA_SOURCE_FILE" "$APP/bin/audiobookshelf"
  else
    [ -s "$DL_DIR/$UPSTREAM_DEB" ] || die "缺少 $UPSTREAM_DEB，请先运行: ./build.sh fetch"
    local EXTRACT_DIR="$BUILD_DIR/extract"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    ( cd "$EXTRACT_DIR" && ar x "$DL_DIR/$UPSTREAM_DEB" data.tar.xz )
    if [ ! -s "$EXTRACT_DIR/data.tar.xz" ]; then
      # 某些 ar 实现成员名不同，列出实际成员
      ( cd "$EXTRACT_DIR" && ar t "$DL_DIR/$UPSTREAM_DEB" ) || true
      die "官方 deb 中未找到 data.tar.xz"
    fi
    tar -xJf "$EXTRACT_DIR/data.tar.xz" -C "$EXTRACT_DIR" \
        ./usr/share/audiobookshelf/audiobookshelf
    [ -s "$EXTRACT_DIR/usr/share/audiobookshelf/audiobookshelf" ] \
      || die "官方 deb 中未找到单文件二进制"
    cp "$EXTRACT_DIR/usr/share/audiobookshelf/audiobookshelf" "$APP/bin/audiobookshelf"
    chmod 0755 "$APP/bin/audiobookshelf"
  fi

  # ffmpeg/ffprobe/libnusqlite3 不随包分发（V6 合规：包内除 SEA 外零预编译
  # ELF；上游 BinaryManager 的替代方案 = unit 设 FFMPEG_PATH/FFPROBE_PATH
  # 指向系统 /usr/bin/* + SKIP_BINARIES_CHECK=1，control 里 Depends: ffmpeg）

  # config.ini（严格 JSON；@@...@@ 占位符渲染）
  log "  + config.ini（External Open: open_path=true, path=/$APP_ID/）"
  sed -e "s|@@VERSION@@|$VERSION_FULL|g" \
      -e "s|@@PUBLISHER@@|$PUBLISHER|g" \
      -e "s|@@PLATFORM@@|$TOS_PLATFORM|g" \
      "$ASSETS_DIR/config.ini.in" > "$APP/config.ini"

  # 多语言文件（文件名必须等于 app id；23 语超集覆盖两个官方口径）
  log "  + $APP_ID.lang（23 语言超集）"
  sed -e "s|@@VERSION@@|$VERSION_FULL|g" \
      "$ASSETS_DIR/$APP_ID.lang" > "$APP/$APP_ID.lang"

  # 图标（透明背景 SVG，viewBox 必须存在；官方 icon.svg）
  log "  + images/icons/$APP_ID.svg"
  cp "$ASSETS_DIR/images/icons/$APP_ID.svg" "$APP/images/icons/$APP_ID.svg"

  # nginx 路由：app 目录内 nginx/ 满足 TOS 规范；同时以 dpkg 实体文件放
  # /etc/nginx/conf.d（beszel/metube 验证过的双落盘模式；postinst 负责校验与自愈）
  log "  + nginx/ + /etc/nginx/conf.d/（127.0.0.1:$APP_PORT 回环反代，前缀保留）"
  mkdir -p "$STAGE_DIR/etc/nginx/conf.d"
  cp "$ASSETS_DIR/nginx/$APP_ID.conf" "$APP/nginx/$APP_ID.conf"
  cp "$ASSETS_DIR/nginx/$APP_ID.conf" "$STAGE_DIR/etc/nginx/conf.d/$APP_ID.conf"

  # systemd 服务：init.d/ 只放主服务（system_id 同名单元）——TOS 应用中心的安装
  # 流程按 init.d 迭代注册服务，多放单元会导致其内部命令失败、
  # "App state will be deleted"、UI 卡"安装中"（真机实证，坑 11）
  log "  + init.d/（仅主服务）+ /etc/systemd/system/（双落盘）"
  mkdir -p "$STAGE_DIR/etc/systemd/system"
  cp "$ASSETS_DIR/init.d/$APP_ID.service" "$APP/init.d/$APP_ID.service"
  cp "$ASSETS_DIR/init.d/$APP_ID.service" "$STAGE_DIR/etc/systemd/system/$APP_ID.service"

  # webui.bz2（WebUI 类应用必填；解压须含可打开的 .html。Audiobookshelf UI
  # 内嵌于 SEA 二进制、经 nginx 路由提供；此处为规范要求的占位前端+隐私政策）
  # 嵌套归档用 python tarfile 打包：uid/gid=0、uname/gname=root、mtime=0
  # （坑 46 S11：macOS bsdtar 的条目属主是打包机用户 uid 501，商店审核
  # 警告 S11；跨平台且不依赖 gnu-tar）
  log "  + webui.bz2（占位前端 + 隐私政策页，归档归主 root:root）"
  local WEBUI_DIR="$BUILD_DIR/webui"
  rm -rf "$WEBUI_DIR"
  mkdir -p "$WEBUI_DIR"
  for f in index.html app.js styles.css privacy-policy.html; do
    sed -e "s|@@VERSION@@|$VERSION_FULL|g" "$ASSETS_DIR/webui/$f" > "$WEBUI_DIR/$f"
  done
  python3 - "$APP/webui.bz2" "$WEBUI_DIR" index.html app.js styles.css privacy-policy.html <<'PYEOF'
import sys, os, tarfile
out, srcdir, *names = sys.argv[1:]
with tarfile.open(out, 'w:bz2') as tf:
    for n in names:
        p = os.path.join(srcdir, n)
        ti = tf.gettarinfo(p, arcname=n)
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = 'root'
        ti.mtime = 0
        ti.mode = 0o644
        with open(p, 'rb') as fh:
            tf.addfile(ti, fh)
PYEOF

  # 配置模板（以 .example 随包分发，postinst 首装复制为正式 env；升级不覆盖）
  log "  + audiobookshelf.env.example 配置模板"
  cp "$ASSETS_DIR/$APP_ID.env" "$APP/$APP_ID.env.example"

  # 官方 deb → 本包的迁移指引（postinst 检测到旧布局时提示阅读）
  cp "$ASSETS_DIR/MIGRATION.md" "$APP/MIGRATION.md"

  # 文档
  cp "$DL_DIR/$LICENSE_FILE" "$STAGE_DIR/usr/share/doc/$APP_ID/copyright"
  {
    echo "$APP_ID ($VERSION_FULL) TOS7; urgency=medium"
    echo ""
    echo "  * 基于 Audiobookshelf 上游 $ABS_VERSION 打包（官方 PPA deb 的单文件 SEA 构建，sha256 校验）"
    echo "  * ffmpeg/ffprobe 改用 TOS 系统包（Depends: ffmpeg，Ubuntu 22.04 universe）"
    echo "  * WebUI External Open：新标签页经 /$APP_ID/ 路由访问，后端仅监听回环 127.0.0.1:$APP_PORT"
    echo "  * 数据目录 /var/lib/$APP_ID（config/metadata），媒体库经 TOS 共享文件夹授权"
    echo ""
    echo " -- $MAINTAINER_FULL  $(date -R 2>/dev/null || date '+%a, %d %b %Y %H:%M:%S %z')"
  } > "$STAGE_DIR/usr/share/doc/$APP_ID/changelog.Debian"

  # 规范清洗：LF 行尾 + 去 BOM（所有文本资产）
  log "  清洗行尾（LF）与 BOM"
  normalize_text \
    "$APP/config.ini" "$APP/$APP_ID.lang" \
    "$APP/nginx/$APP_ID.conf" \
    "$STAGE_DIR/etc/nginx/conf.d/$APP_ID.conf" \
    "$APP/init.d/"*.service \
    "$STAGE_DIR/etc/systemd/system/"*.service \
    "$APP/"*.example \
    "$APP/MIGRATION.md" \
    "$STAGE_DIR/usr/share/doc/$APP_ID/changelog.Debian"

  # 清理 macOS 扩展属性，避免污染 tar（AppleDouble / quarantine；坑 8）
  if command -v xattr >/dev/null 2>&1; then
    xattr -rc "$STAGE_DIR" >/dev/null 2>&1 || true
  fi
  find "$STAGE_DIR" -name '._*' -delete 2>/dev/null || true
  find "$STAGE_DIR" -name '.DS_Store' -delete 2>/dev/null || true

  log "组装完成"
}

# ============================================================
# 阶段: verify —— 目标架构与规范关键项校验
# ============================================================
stage_verify() {
  local APP="$STAGE_DIR/usr/local/$APP_ID"
  [ -d "$APP" ] || die "尚未组装，请先运行: ./build.sh stage"
  local fail=0

  log "校验规范关键路径..."
  local p
  for p in "$APP/config.ini" "$APP/$APP_ID.lang" \
           "$APP/images/icons/$APP_ID.svg" \
           "$APP/nginx/$APP_ID.conf" \
           "$APP/init.d/$APP_ID.service" \
           "$STAGE_DIR/etc/systemd/system/$APP_ID.service" \
           "$STAGE_DIR/etc/nginx/conf.d/$APP_ID.conf" \
           "$APP/bin/audiobookshelf" \
           "$APP/webui.bz2" \
           "$APP/$APP_ID.env.example" \
           "$APP/MIGRATION.md" \
           "$STAGE_DIR/usr/share/doc/$APP_ID/copyright"; do
    [ -e "$p" ] || { warn "缺失: ${p#$STAGE_DIR/}"; fail=1; }
  done

  log "校验 config.ini（JSON 合法性 / 互斥字段 / 版本一致性）..."
  python3 - "$APP/config.ini" "$VERSION_FULL" "$TOS_PLATFORM" "$APP_ID" <<'PYEOF' || fail=1
import json, sys
cfg_path, want_ver, want_plat, app_id = sys.argv[1:5]
cfg = json.load(open(cfg_path))
errs = []
if cfg.get("id") != app_id: errs.append(f"id != {app_id}")
if cfg.get("version") != want_ver: errs.append(f"version != {want_ver}")
if cfg.get("system_id") != app_id: errs.append("system_id 不一致")
if cfg.get("package") != app_id: errs.append("package 不一致")
if cfg.get("platform") != want_plat: errs.append(f"platform != {want_plat}")
# WebUI External Open: open_path=true 且不得出现 type；path=/<id>/
if cfg.get("open_path") is not True: errs.append("open_path 必须为 true")
if "type" in cfg: errs.append("不得包含 type 字段（与 open_path 互斥）")
if cfg.get("path") != f"/{app_id}/": errs.append(f"path 必须为 /{app_id}/")
if cfg.get("user") != app_id: errs.append(f"user 应为 {app_id}")
if cfg.get("recommend") is not False: errs.append("recommend 提交时必须为 false")
if cfg.get("beta") is not False: errs.append("beta 必须为 false（坑 41）")
import re
if not re.fullmatch(r"/[a-z0-9_-]+/", cfg.get("path","")): errs.append("path 必须为 /<id>/ 路由格式（坑 37 C21）")
if not str(cfg.get("official","")).startswith("http"): errs.append("official 必须为可机器 GET 的源码 URL（坑 30a）")
for e in errs:
    print(f"    校验失败: {e}", file=sys.stderr)
sys.exit(1 if errs else 0)
PYEOF

  log "校验 .lang（23 语超集齐全）..."
  local lang_missing
  lang_missing=$(python3 - "$APP/$APP_ID.lang" <<'PYEOF'
import sys
# 真机 14 语 + 官方英文文档口径 9 语的超集（指南 §二 推荐的稳妥解）
required = ["zh-cn","zh-hk","en-us","fr-fr","de-de","it-it","es-es",
            "hu-hu","ja-jp","ko-kr","pl-pl","ru-ru","tr-tr","pt-pt",
            "ar-sa","cs-cz","he-il","id-id","nb-no","nl-nl","sv-se",
            "th-th","vi-vn"]
text = open(sys.argv[1], encoding="utf-8").read()
missing = [t for t in required if f"[{t}]" not in text]
print(",".join(missing))
PYEOF
)
  [ -z "$lang_missing" ] || { warn "lang 缺少语言节: $lang_missing"; fail=1; }

  # V11 双重门禁（坑 41）：beta 不仅看 config.ini 字段，还要扫 lang 全文
  # ——审查是机器全文匹配，不分语言，descript/release_note 里都不能出现
  log "校验 lang 全文无 beta 字样（坑 41 V11）..."
  local beta_hits
  beta_hits=$(grep -ciE '\bbeta\b|\balpha\b|\brc[0-9]\b' "$APP/$APP_ID.lang" || true)
  [ "$beta_hits" -eq 0 ] || { warn "lang 含 $beta_hits 处 beta/alpha/rc 字样（V11 风险）"; fail=1; }

  # 版本三处一致（config.ini / control / lang）
  log "校验版本三处一致（$VERSION_FULL）..."
  grep -q "\"version\": \"$VERSION_FULL\"" "$APP/config.ini" \
    || { warn "config.ini version 不一致"; fail=1; }
  grep -q "^version      = \"$VERSION_FULL\"" "$APP/$APP_ID.lang" \
    || { warn "lang version 不一致"; fail=1; }

  # init.d 必须恰好一个服务文件（TOS 应用中心兼容性，真机实证，坑 11）
  local n_initd
  n_initd=$(ls "$APP/init.d/"*.service 2>/dev/null | wc -l | tr -d ' ')
  [ "$n_initd" = "1" ] || { warn "init.d/ 必须只含主服务（当前 $n_initd 个）"; fail=1; }

  log "校验 systemd 服务（禁 Restart/必配 StartLimit/禁 ExecStart 变量展开）..."
  local svc
  for svc in "$APP/init.d/"*.service \
             "$STAGE_DIR/etc/systemd/system/"*.service; do
    grep -q '^\[Unit\]' "$svc" || { warn "非 systemd unit: $svc"; fail=1; }
    grep -Eq '^Restart' "$svc" && { warn "规范禁止配置 Restart: $svc"; fail=1; }
    grep -Eq '^ExecStart=.*\$' "$svc" && { warn "ExecStart 禁用变量展开（坑 1）: $svc"; fail=1; }
    grep -q '^StartLimitBurst=' "$svc" || { warn "缺少 StartLimitBurst: $svc"; fail=1; }
    grep -q '^StartLimitIntervalSec=' "$svc" || { warn "缺少 StartLimitIntervalSec: $svc"; fail=1; }
    grep -q "^User=$APP_USER" "$svc" || { warn "必须 User=$APP_USER: $svc"; fail=1; }
    grep -q "^ExecStart=/usr/local/$APP_ID/bin/" "$svc" \
      || { warn "ExecStart 必须指向 /usr/local/$APP_ID/bin: $svc"; fail=1; }
    # ffmpeg 系统化配置（V6）：unit 必须设 SKIP_BINARIES_CHECK 且指向系统路径，
    # 否则上游 BinaryManager 会因版本白名单（5.1 vs 系统 4.4）触发在线下载（S8）
    grep -q '^Environment=SKIP_BINARIES_CHECK=1' "$svc" \
      || { warn "unit 缺 SKIP_BINARIES_CHECK=1（S8 风险）: $svc"; fail=1; }
    grep -q '^Environment=FFMPEG_PATH=/usr/bin/ffmpeg' "$svc" \
      || { warn "FFMPEG_PATH 应指向系统 ffmpeg: $svc"; fail=1; }
  done

  log "校验 webui.bz2（含 .html / 归档属主 root:root / mtime 归零）..."
  # 坑 33：pipefail 下 grep -q 早退会让上游 tar 收 SIGPIPE（141）导致假失败，
  # 改计数式；坑 46 S11：嵌套归档条目 uid/gid 必须 0（uid 501 = 打包机用户）
  python3 - "$APP/webui.bz2" <<'PYEOF' || fail=1
import sys, tarfile
errs = []
with tarfile.open(sys.argv[1], 'r:bz2') as tf:
    members = tf.getmembers()
if not any(m.name.endswith('.html') for m in members):
    errs.append("缺少 .html 入口")
if not any(m.name == 'privacy-policy.html' for m in members):
    errs.append("缺少 privacy-policy.html（坑 45 C3）")
for m in members:
    if m.uid != 0 or m.gid != 0:
        errs.append(f"条目属主非 root: {m.name} uid={m.uid} gid={m.gid}（坑 46 S11）")
    if m.mtime != 0:
        errs.append(f"条目 mtime 未归零: {m.name}")
for e in errs:
    print(f"    校验失败: {e}", file=sys.stderr)
sys.exit(1 if errs else 0)
PYEOF

  log "校验 nginx 隐私政策精确路由（坑 45 C3：可达 ≠ 可发现）..."
  grep -q 'location = /audiobookshelf/privacy-policy.html' \
    "$APP/nginx/$APP_ID.conf" \
    || { warn "nginx 缺隐私政策精确路由"; fail=1; }

  log "校验图标 SVG 完整性（坑 47：XML 可解析/viewBox/fill/path 截断检测）..."
  python3 - "$APP/images/icons/$APP_ID.svg" <<'PYEOF' || fail=1
import sys
import xml.etree.ElementTree as ET
path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except ET.ParseError as e:
    print(f"    SVG XML 解析失败（疑似下载截断）: {e}", file=sys.stderr)
    sys.exit(1)
errs = []
if 'viewBox' not in root.attrib:
    errs.append("根元素缺 viewBox")
paths = root.iter('{http://www.w3.org/2000/svg}path')
nd = sum(1 for p in paths for _ in [0] if p.get('d'))
if nd == 0:
    errs.append("无任何带 d 属性的 path（疑似截断或空图标）")
for e in errs:
    print(f"    校验失败: {e}", file=sys.stderr)
sys.exit(1 if errs else 0)
PYEOF

  log "校验 SEA 架构与加壳状态（目标: $ELF_ARCH —— 坑 28/43 防呆）..."
  # 坑 33：echo|grep -q 在 pipefail 下有 SIGPIPE 假失败风险，先落变量再 case
  local bin_desc
  bin_desc=$(file "$APP/bin/audiobookshelf")
  case "$bin_desc" in
    *"ELF"*"$ELF_ARCH"*) log "  ok: audiobookshelf -> $(echo "$bin_desc" | cut -d: -f2 | cut -c1-80)" ;;
    *) warn "错误架构: bin/audiobookshelf -> $bin_desc"; fail=1 ;;
  esac
  case "$bin_desc" in
    *"dynamically linked"*) : ;;  # 预期：glibc 动态链接（Ubuntu 22.04 基座）
    *) warn "SEA 非动态链接（预期 dynamically linked glibc），请人工复核" ;;
  esac
  case "$bin_desc" in
    *"no section header"*) warn "SEA 疑似加壳（UPX 类，观感即黑盒，坑 43）"; fail=1 ;;
  esac

  # V6 硬门禁（坑 31/30/30a）：包内除 SEA 外零预编译 ELF。ffmpeg/ffprobe/
  # libnusqlite3 走系统包/不加载；一旦这里报数 > 1，说明有人把预编译二进制
  # 塞回了包里——商店审核会用 file 扫 ELF 计数，一票否决
  log "V6 门禁：包内 ELF 计数（除 SEA 外必须为 0）..."
  local elf_total elf_extra
  elf_total=$(find "$STAGE_DIR" -type f -exec file {} + 2>/dev/null | grep -c "ELF" || true)
  elf_extra=$((elf_total - 1))
  if [ "$elf_extra" -gt 0 ]; then
    warn "发现 $elf_extra 个额外 ELF（V6 一票否决项）:"
    find "$STAGE_DIR" -type f -exec file {} + 2>/dev/null | grep "ELF" | grep -v "bin/audiobookshelf" || true
    fail=1
  else
    log "  ok: 仅 bin/audiobookshelf 一个 ELF"
  fi

  log "检查 macOS Mach-O 混入（应为 0）..."
  local n_macho
  n_macho=$(find "$APP" -type f -exec file {} + 2>/dev/null | grep -c "Mach-O" || true)
  [ "$n_macho" -eq 0 ] || { warn "发现 $n_macho 个 Mach-O 文件！"; fail=1; }

  log "S8 零网络断言（deb 内脚本不得在线安装，审查员同款扫法，坑 15）..."
  local s8_hits
  s8_hits=$(grep -rnE '(pip install|npm install|apt(-get)? install|yarn add|pnpm install|curl -fsSL https|wget -qO- https?://(get|install))' \
      "$STAGE_DIR/DEBIAN" "$ASSETS_DIR" 2>/dev/null | grep -v '^\s*#' || true)
  [ -z "$s8_hits" ] || { warn "发现疑似在线安装语句:"$'\n'"$s8_hits"; fail=1; }
  # 解包后无 ._ AppleDouble 残留（坑 8）
  local n_ad
  n_ad=$(find "$STAGE_DIR" -name '._*' -o -name '.DS_Store' | wc -l | tr -d ' ')
  [ "$n_ad" -eq 0 ] || { warn "发现 $n_ad 个 AppleDouble/.DS_Store 残留"; fail=1; }

  if [ "$fail" -eq 0 ]; then
    log "校验通过 ✅"
  else
    die "校验失败，请检查上方警告"
  fi
}

# ============================================================
# 阶段: deb —— 生成 .deb + 上架资产
# ============================================================
stage_deb() {
  [ -d "$STAGE_DIR/usr/local/$APP_ID" ] || die "尚未组装，请先运行: ./build.sh stage"
  mkdir -p "$OUT_DIR"
  # shellcheck source=makedeb.sh
  "$SCRIPT_DIR/makedeb.sh" "$STAGE_DIR" "$ASSETS_DIR" "$DEB_FILE" \
    "$VERSION_FULL" "$TARGET_ARCH" "$MAINTAINER_FULL"

  # Release 资产命名（版本由 Release tag 表达）+ 上架要求的 sha256
  cp "$DEB_FILE" "$STORE_DEB"
  sha256_of "$STORE_DEB" | awk '{print $1"  "$2}' > "$STORE_DEB.sha256"
  log "完成: $DEB_FILE"
  log "上架资产: $STORE_DEB (+ .sha256；Release tag 须为 v$VERSION_FULL)"
}

stage_info() {
  cat <<EOF
Audiobookshelf 版本: $ABS_VERSION (完整版本 $VERSION_FULL)
目标架构      : $TARGET_ARCH (TOS:$TOS_PLATFORM)
TOS app id    : $APP_ID（新标签页 /$APP_ID/，后端 127.0.0.1:$APP_PORT）
上游 deb      : $UPSTREAM_DEB (sha256 ${UPSTREAM_DEB_SHA256:0:16}...)
ffmpeg 策略   : TOS 系统包（Depends: ffmpeg，unit 设 SKIP_BINARIES_CHECK=1）
产物          : $DEB_FILE
上架资产      : $STORE_DEB + .sha256（Release tag: v$VERSION_FULL）
EOF
}

stage_clean() {
  rm -rf "$STAGE_DIR" "$BUILD_DIR/webui" "$BUILD_DIR/extract"
  log "已清理 stage（保留下载缓存）"
}

stage_distclean() {
  rm -rf "$BUILD_DIR" "$OUT_DIR"
  log "已清理全部构建产物与下载缓存"
}

# ============================================================
# 入口
# ============================================================
STAGE=${1:-all}
case "$STAGE" in
  fetch)      stage_fetch ;;
  stage)      stage_stage ;;
  deb)        stage_deb ;;
  all)        stage_fetch; stage_stage; stage_verify; stage_deb ;;
  clean)      stage_clean ;;
  distclean)  stage_distclean ;;
  verify)     stage_verify ;;
  info)       stage_info ;;
  *)          die "未知阶段: $STAGE（可用: fetch stage deb verify clean distclean info）" ;;
esac
