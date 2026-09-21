#!/usr/bin/env bash
# repro-build.sh — 审核者一键复现 SEA 构建（V6 材料，D-015）
# 用法: ./scripts/repro-build.sh [上游版本，默认读取 config.env 的 ABS_VERSION]
# 依赖: curl、tar、Node.js 20.11.1、npm（或直接用 Dockerfile.repro 免装依赖）
#
# 命令序列与上游 advplyr/audiobookshelf 的 build/linuxpackager 逐字一致；
# 与 .github/workflows/build-sea.yml 的 CI 步骤同源。
set -euo pipefail

ABS_VERSION="${1:-$(sed -n 's/^ABS_VERSION=//p' "$(dirname "$0")/../config.env")}"
NODE_VERSION=20.11.1
OUT=audiobookshelf-sea-x86_64

command -v node >/dev/null || { echo "需要 Node.js ${NODE_VERSION}"; exit 1; }
nv=$(node -v | tr -d v)
[ "$nv" = "$NODE_VERSION" ] || echo "警告: Node 版本 $nv ≠ 配方锁定 $NODE_VERSION（工具链护栏）" >&2

echo "==> 下载上游源码 v${ABS_VERSION}"
curl -fL --retry 5 -o /tmp/abs-src.tar.gz \
  "https://github.com/advplyr/audiobookshelf/archive/refs/tags/v${ABS_VERSION}.tar.gz"
sha256sum /tmp/abs-src.tar.gz

rm -rf /tmp/abs-repro && mkdir -p /tmp/abs-repro
tar -xzf /tmp/abs-src.tar.gz -C /tmp/abs-repro --strip-components=1
cd /tmp/abs-repro

echo "==> 构建客户端（Nuxt generate）"
cd client
rm -rf node_modules
npm ci --unsafe-perm=true --allow-root
npm run generate
cd ..

echo "==> 构建服务端依赖 + pkg 打包"
rm -rf node_modules
npm ci --unsafe-perm=true --allow-root
npx --yes @yao-pkg/pkg@6.22.0 -t node20-linux-x64 -o "$(dirname "$PWD")/$OUT" .

echo "==> 完成: $OUT"
file "$(dirname "$PWD")/$OUT"
sha256sum "$(dirname "$PWD")/$OUT"
