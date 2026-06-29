#!/bin/bash
# CodeWhisper 一键构建 + 打包脚本
# 流程：xcodegen 生成工程 -> xcodebuild 构建 Release .app -> ad-hoc 签名 -> 制作单文件 dmg
# 用法：./scripts/build_dmg.sh
set -euo pipefail

# ---------- 基本变量 ----------
APP_NAME="CodeWhisper"
SCHEME="CodeWhisper"
CONFIGURATION="Release"
ARCH="arm64"

# 内置模型 variant（默认中文 turbo 632MB，可用环境变量 MODEL_VARIANT 覆盖）
# 名字必须与 AppSettings 默认值、mac/Models 下目录名三处保持一致
MODEL_VARIANT="${MODEL_VARIANT:-openai_whisper-large-v3-v20240930_turbo_632MB}"

# 解析仓库根目录（脚本位于 <repo>/scripts/ 下）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAC_DIR="${REPO_ROOT}/mac"

# 构建产物与中间目录
DERIVED_DATA="${MAC_DIR}/build"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

# dmg 相关
DMG_PATH="${REPO_ROOT}/${APP_NAME}.dmg"
STAGING_DIR="${MAC_DIR}/build/dmg-staging"

echo "==> 仓库根：${REPO_ROOT}"
echo "==> 工程目录：${MAC_DIR}"

# ---------- 步骤 1：生成 Xcode 工程 ----------
echo "==> [1/6] xcodegen generate"
cd "${MAC_DIR}"
xcodegen generate

# ---------- 步骤 2：构建 Release .app（arm64，ad-hoc 签名） ----------
echo "==> [2/6] xcodebuild ${CONFIGURATION} (${ARCH}, ad-hoc 签名)"
xcodebuild \
  -project "${MAC_DIR}/${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -arch "${ARCH}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

# ---------- 步骤 3：定位 .app 产物 ----------
echo "==> [3/6] 定位产物：${APP_PATH}"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "错误：未找到构建产物 ${APP_PATH}" >&2
  exit 1
fi

# ---------- 步骤 3.5：内置离线模型（必须在 codesign 之前） ----------
# 若 mac/Models/<variant>/ 存在，则把整个模型目录拷进 .app 的 Resources/Models/<variant>，
# 使 App 离线开箱即用。codesign --deep 会随后对拷入的资源一并签名。
MODEL_SRC="${MAC_DIR}/Models/${MODEL_VARIANT}"
MODEL_DEST_DIR="${APP_PATH}/Contents/Resources/Models/${MODEL_VARIANT}"
if [[ -d "${MODEL_SRC}" ]]; then
  echo "==> [3.5/6] 内置模型：${MODEL_VARIANT}"
  # 幂等：先清掉旧的同名目录，避免残留
  rm -rf "${MODEL_DEST_DIR}"
  mkdir -p "${MODEL_DEST_DIR}"
  # 用 rsync -a 完整拷贝（含 .mlmodelc 子目录、保留属性），结尾斜杠拷贝目录内容
  rsync -a "${MODEL_SRC}/" "${MODEL_DEST_DIR}/"
  echo "==> 模型已内置：${MODEL_DEST_DIR}（$(du -sh "${MODEL_DEST_DIR}" | cut -f1)）"
else
  echo "==> [3.5/6] 跳过内置模型：未找到 ${MODEL_SRC}（App 将在首次运行时联网下载）"
fi

# ---------- 步骤 3.6：内置 tokenizer（必须在 codesign 之前） ----------
# 若 mac/Models/tokenizer/ 存在，则拷进 .app 的 Resources/Models/tokenizer，
# 目标路径必须严格与代码 Bundle.main.resourcePath + "/Models/tokenizer" 一致，
# 否则离线分支命不中。codesign --deep 会随后对拷入的资源一并签名。
TOKENIZER_SRC="${MAC_DIR}/Models/tokenizer"
TOKENIZER_DEST_DIR="${APP_PATH}/Contents/Resources/Models/tokenizer"
if [[ -d "${TOKENIZER_SRC}" ]]; then
  echo "==> [3.6/6] 内置 tokenizer"
  # 幂等：先清掉旧目录，避免残留
  rm -rf "${TOKENIZER_DEST_DIR}"
  mkdir -p "${TOKENIZER_DEST_DIR}"
  # 用 rsync -a 完整拷贝（保留属性），结尾斜杠拷贝目录内容
  rsync -a "${TOKENIZER_SRC}/" "${TOKENIZER_DEST_DIR}/"
  echo "==> tokenizer 已内置：${TOKENIZER_DEST_DIR}（$(du -sh "${TOKENIZER_DEST_DIR}" | cut -f1)）"
else
  echo "==> [3.6/6] 跳过内置 tokenizer：未找到 ${TOKENIZER_SRC}"
fi

# ---------- 步骤 4：ad-hoc 强制签名（确保可启动） ----------
echo "==> [4/6] codesign ad-hoc 强制签名"
codesign --force --deep --sign - "${APP_PATH}"
# 验证签名
codesign --verify --verbose "${APP_PATH}"

# ---------- 步骤 5：制作单文件 dmg ----------
echo "==> [5/6] 制作 dmg"
# 清理旧产物，保证幂等
rm -rf "${STAGING_DIR}"
rm -f "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

# 干净 staging：仅包含 .app + 指向 /Applications 的软链
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# 优先用 create-dmg，失败则回退 hdiutil
if command -v create-dmg >/dev/null 2>&1; then
  echo "==> 使用 create-dmg"
  # create-dmg 自己创建 Applications 软链与布局，因此从临时目录单独喂 .app
  CREATE_DMG_SRC="${MAC_DIR}/build/dmg-src"
  rm -rf "${CREATE_DMG_SRC}"
  mkdir -p "${CREATE_DMG_SRC}"
  cp -R "${APP_PATH}" "${CREATE_DMG_SRC}/"

  if create-dmg \
      --volname "${APP_NAME}" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "${APP_NAME}.app" 150 200 \
      --app-drop-link 450 200 \
      --no-internet-enable \
      "${DMG_PATH}" \
      "${CREATE_DMG_SRC}"; then
    echo "==> create-dmg 成功"
  else
    echo "==> create-dmg 失败，回退 hdiutil"
    rm -f "${DMG_PATH}"
    hdiutil create \
      -volname "${APP_NAME}" \
      -srcfolder "${STAGING_DIR}" \
      -ov -format UDZO \
      "${DMG_PATH}"
  fi
  rm -rf "${CREATE_DMG_SRC}"
else
  echo "==> 未安装 create-dmg，使用 hdiutil"
  hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"
fi

# 清理 staging
rm -rf "${STAGING_DIR}"

# ---------- 步骤 6：打印结果 ----------
echo "==> [6/6] 完成"
ls -lh "${DMG_PATH}"
