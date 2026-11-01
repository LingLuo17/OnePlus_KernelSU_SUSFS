#!/usr/bin/env bash
set -eo pipefail

VARIANT="${KSU_VARIANT}"

case "$VARIANT" in
  "SukiSU") REPO="SukiSU-Ultra/SukiSU-Ultra"; KSUM="manager"; EXPECTED_BRANCH="main" ;;
  "BakaSU") REPO="Baka-SU/BakaSU";           KSUM="manager"; EXPECTED_BRANCH="main" ;;
  "FinaSU") REPO="LyraVoid/FinaSU";          KSUM="manager"; EXPECTED_BRANCH="master" ;;
  *) echo "::error::未知变体: $VARIANT"; exit 1 ;;
esac

# 通道兜底解析（选择步骤异常时仍能按输入判断）
CHANNEL_KIND="${CHANNEL_KIND:-}"
PIN_MODE="${PIN_MODE:-}"
if [ -z "$CHANNEL_KIND" ]; then
  case "${BUILD_CHANNEL}" in
    最新*|latest*|HEAD*) CHANNEL_KIND="latest"; PIN_MODE="head" ;;
    *)                   CHANNEL_KIND="release"; PIN_MODE="pin" ;;
  esac
fi

ksu_version_of() {
  case "$1" in
    SukiSU) echo $((40000 + $2 - 2815)) ;;
    BakaSU) echo $((30700 + $2)) ;;
    FinaSU) echo $((30000 + $2)) ;;
  esac
}

mkdir -p manager-artifacts

# ==================== A. 正式通道：官方 Release 管理器 ====================
if [ "${MANAGER_SOURCE:-ci}" = "release" ] && [ -n "${REL_APK_URL:-}" ]; then
  echo "正式通道：下载 Release $REL_TAG 的管理器（$REL_APK_NAME）..."
  REL_APK="manager-artifacts/$(basename "$REL_APK_NAME")"
  if curl -sL --fail --retry 3 --max-time 300 -o "$REL_APK" "$REL_APK_URL"; then
    # 先剥离 ABI 段再提取版本，避免 x86_64 的 "_64" 等数字尾巴被误当成 versionCode
    CLEAN_NAME=$(basename "$REL_APK" | sed -E 's/-(arm64-v8a|armeabi-v7a|armv7|riscv64|x86_64|x86|universal)-release\.apk$/.apk/')
    MANAGER_VERSION=$(echo "$CLEAN_NAME" | grep -oE '_[0-9]+' | tail -n 1 | tr -d '_')
    if [[ "${MANAGER_VERSION:-}" =~ ^[0-9]+$ ]]; then
      echo "Release 管理器版本: $MANAGER_VERSION（标签 $REL_TAG，提交 ${REL_COMMIT:0:8}）"
      echo "MANAGER_VERSION=$MANAGER_VERSION" >> $GITHUB_ENV
      {
        echo "managerVer=$MANAGER_VERSION"
        echo "ksuCommit=$REL_COMMIT"
        echo "ksuBranch=$REL_TAG"
        echo "channelTag=$REL_TAG"
      } >> $GITHUB_OUTPUT

      # 版本一致性自检：Release 标签提交对应的 KSU 版本应与管理器 versionCode 相同
      REL_COUNT=$(git -C KernelSU rev-list --count "$REL_COMMIT" 2>/dev/null || echo "")
      if [ -n "$REL_COUNT" ]; then
        REL_KSU_VERSION=$(ksu_version_of "$VARIANT" "$REL_COUNT")
        if [ "$MANAGER_VERSION" != "$REL_KSU_VERSION" ]; then
          echo "::warning::Release 管理器版本 $MANAGER_VERSION 与标签提交对应的 KSU 版本 $REL_KSU_VERSION 不一致"
        fi
      fi

      if [ "$VARIANT" == "FinaSU" ]; then
        # 从该 Release 的管理器 APK 提取签名证书（DER），供内核侧第二信任槽
        # （EXPECTED_SIZE2/EXPECTED_HASH2）对齐。FinaSU 的内核只信任槽内
        # 签名的管理器，不注入证书时 root 会被官方 KernelSU 管理器抢占
        echo "从 Release 管理器 APK 提取签名证书..."
        CERT_INFO=$(python3 "$GITHUB_WORKSPACE/scripts/finasu_compat/extract_manager_cert.py" "$REL_APK" | head -n1)
        if [ -n "$CERT_INFO" ]; then
          CERT_SIZE=$(echo "$CERT_INFO" | awk '{print $1}')
          CERT_HASH=$(echo "$CERT_INFO" | awk '{print $2}')
          echo "managerCertSize=$CERT_SIZE" >> $GITHUB_OUTPUT
          echo "managerCertHash=$CERT_HASH" >> $GITHUB_OUTPUT
          echo "Release 管理器证书: size=$CERT_SIZE sha256=$CERT_HASH"
        else
          echo "::warning::未能从 Release 管理器 APK 提取签名证书，内核侧将回退到最新 Release APK 提取"
        fi
      fi
      echo "MANAGER_FETCH_OK=true" >> $GITHUB_ENV
      exit 0
    fi
    echo "::warning title=正式通道回退::无法从 Release 管理器文件名解析版本（$(basename "$REL_APK")），改用官方默认分支构建"
  else
    echo "::warning title=正式通道回退::Release 管理器下载失败，改用官方默认分支构建"
  fi
  rm -rf manager-artifacts && mkdir -p manager-artifacts
fi

# ==================== B. FinaSU 正式通道：Release 管理器 ====================
# 最新通道走下方 CI 构建路径，取 build-manager.yml 的最新产物。
if [ "$VARIANT" == "FinaSU" ] && [ "$PIN_MODE" != "head" ]; then
  echo "FinaSU：管理器取最新 Release APK..."
  REL_JSON=""
  for ATTEMPT in 1 2 3; do
    REL_JSON=$(curl -s --fail --max-time 30 -H "Authorization: token ${GH_TOKEN}" \
      "https://api.github.com/repos/LyraVoid/FinaSU/releases/latest") && [ -n "$REL_JSON" ] && break
    echo "获取 FinaSU 最新 Release 失败，重试 ($ATTEMPT/3)..."
    sleep 5
  done
  [ -z "$REL_JSON" ] && { echo "无法获取 FinaSU 最新 Release 信息"; exit 1; }

  REL_TAG=$(printf '%s' "$REL_JSON" | jq -r '.tag_name')
  REL_APK_URL=$(printf '%s' "$REL_JSON" | jq -r '[.assets[] | select(.name | endswith("-release.apk"))][0].browser_download_url')
  # /releases/latest 不含 pre-release；无 APK 资产时回退检索最近 10 个 Release
  if [ -z "$REL_APK_URL" ] || [ "$REL_APK_URL" = "null" ]; then
    echo "Release $REL_TAG 中无 APK 资产，回退检索最近 Release 列表..."
    REL_LIST=$(curl -s --fail --max-time 30 -H "Authorization: token ${GH_TOKEN}" \
      "https://api.github.com/repos/LyraVoid/FinaSU/releases?per_page=10")
    REL_APK_URL=$(printf '%s' "$REL_LIST" | jq -r '[.[] | select(.draft == false) | .assets[] | select(.name | endswith("-release.apk")) | .browser_download_url][0]')
  fi
  if [ -z "$REL_APK_URL" ] || [ "$REL_APK_URL" = "null" ]; then
    echo "FinaSU 最近的 Release 中均未找到管理器 APK"
    exit 1
  fi

  echo "下载 FinaSU 发行版管理器: Release $REL_TAG"
  rm -rf manager-artifacts
  mkdir -p manager-artifacts
  APK_NAME=$(basename "$REL_APK_URL")
  if ! curl -sL --fail --retry 3 --max-time 300 -o "manager-artifacts/$APK_NAME" "$REL_APK_URL"; then
    echo "下载 FinaSU 管理器失败: $REL_APK_URL"
    exit 1
  fi
  APK_FILE="manager-artifacts/$APK_NAME"

  # APK 文件名形如 FinaSU_v1.0.10_33030-release.apk，末段数字即 versionCode
  CLEAN_NAME=$(basename "$APK_FILE" | sed -E 's/-(arm64-v8a|armeabi-v7a|armv7|riscv64|x86_64|x86|universal)-release\.apk$/.apk/')
  ACTUAL_VERSION=$(echo "$CLEAN_NAME" | grep -oE '_[0-9]+' | tail -n 1 | tr -d '_')
  if ! [[ "$ACTUAL_VERSION" =~ ^[0-9]+$ ]]; then
    echo "无法从 FinaSU 管理器 APK 文件名解析版本 ($(basename "$APK_FILE"))"
    exit 1
  fi
  MANAGER_VERSION="$ACTUAL_VERSION"

  # 最新：内核锁定 master HEAD；正式回退：锁定 Release 标签提交
  if [ "$PIN_MODE" = "head" ]; then
    KSU_COMMIT=$(git -C KernelSU rev-parse "origin/${EXPECTED_BRANCH}^{commit}" 2>/dev/null \
      || git ls-remote "https://github.com/LyraVoid/FinaSU.git" "refs/heads/${EXPECTED_BRANCH}" 2>/dev/null | awk '{print $1}')
  else
    KSU_COMMIT=$(git -C KernelSU rev-parse "${REL_TAG}^{commit}" 2>/dev/null \
      || git ls-remote "https://github.com/LyraVoid/FinaSU.git" "refs/tags/${REL_TAG}^{}" 2>/dev/null | awk '{print $1}')
  fi
  if [ -z "$KSU_COMMIT" ]; then
    echo "::warning::无法解析内核对齐提交，内核侧将跟随默认分支 HEAD"
  else
    PIN_COUNT=$(git -C KernelSU rev-list --count "$KSU_COMMIT" 2>/dev/null || echo "")
    if [ -n "$PIN_COUNT" ]; then
      echo "内核 KSU 版本将对齐 ${KSU_COMMIT:0:8}: $(ksu_version_of "$VARIANT" "$PIN_COUNT")"
    fi
  fi

  # 提取管理器签名证书（DER size + sha256），供内核侧第二信任槽
  # （EXPECTED_SIZE2/HASH2）对齐；不注入时内核信任上游 KernelSU 默认槽，
  # root 会被官方 KernelSU 管理器抢占、FinaSU 管理器显示"未安装"
  CERT_INFO=$(python3 "$GITHUB_WORKSPACE/scripts/finasu_compat/extract_manager_cert.py" "$APK_FILE" | head -n1)
  if [ -z "$CERT_INFO" ]; then
    echo "::error::未能从 FinaSU 管理器 APK 提取签名证书"
    exit 1
  fi
  CERT_SIZE=$(echo "$CERT_INFO" | awk '{print $1}')
  CERT_HASH=$(echo "$CERT_INFO" | awk '{print $2}')
  echo "管理器签名证书: size=$CERT_SIZE sha256=$CERT_HASH"

  echo "选择 FinaSU Release $REL_TAG, APK 实测版本 $MANAGER_VERSION"
  echo "MANAGER_VERSION=$MANAGER_VERSION" >> $GITHUB_ENV
  echo "managerVer=$MANAGER_VERSION" >> $GITHUB_OUTPUT
  echo "ksuCommit=$KSU_COMMIT" >> $GITHUB_OUTPUT
  echo "ksuBranch=$REL_TAG" >> $GITHUB_OUTPUT
  echo "managerCertSize=$CERT_SIZE" >> $GITHUB_OUTPUT
  echo "managerCertHash=$CERT_HASH" >> $GITHUB_OUTPUT
  echo "MANAGER_FETCH_OK=true" >> $GITHUB_ENV
  exit 0
fi

# ==================== C. SukiSU / BakaSU / FinaSU(latest)：官方 CI 构建的管理器 ====================
# 最新通道：SukiSU/BakaSU 先锁定默认分支 HEAD，并把管理器限定为「版本与该 HEAD 一致」的构建，
# 避免出现内核 35249 / 管理器 35248 这种版本错位。FinaSU 以最新构建产物的提交为准。
HEAD_SHA=""
HEAD_VERSION=""
if [ "$PIN_MODE" = "head" ] && [ "$VARIANT" != "FinaSU" ]; then
  HEAD_SHA=$(git -C KernelSU rev-parse "origin/${EXPECTED_BRANCH}^{commit}" 2>/dev/null || true)
  if [ -z "$HEAD_SHA" ]; then
    HEAD_SHA=$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$EXPECTED_BRANCH" 2>/dev/null | awk '{print $1}')
  fi
  if [ -n "$HEAD_SHA" ]; then
    git -C KernelSU cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || git -C KernelSU fetch -q origin "$HEAD_SHA" 2>/dev/null || true
    HEAD_COUNT=$(git -C KernelSU rev-list --count "$HEAD_SHA" 2>/dev/null || echo "")
    if [ -n "$HEAD_COUNT" ]; then
      HEAD_VERSION=$(ksu_version_of "$VARIANT" "$HEAD_COUNT")
    fi
    echo "最新通道：$EXPECTED_BRANCH HEAD ${HEAD_SHA:0:8} 对应 KSU 版本 ${HEAD_VERSION:-未知}"
  else
    echo "::warning::无法解析 $EXPECTED_BRANCH HEAD，管理器按最新构建选择"
  fi
fi

FILENAME="build-manager.yml"

get_manager_artifacts() {
  local artifacts="$1"
  if [ "$VARIANT" == "BakaSU" ]; then
    printf '%s' "$artifacts" | jq -r \
      '.artifacts[] | select(.name == "Manager-release" or .name == "Spoofed-Manager-release") | "\(.name)\t\(.archive_download_url)"'
  elif [ "$VARIANT" == "FinaSU" ]; then
    # FinaSU 同时上传 manager-gradle / manager-check-reports / manager；
    # 只有 manager 是重新签名后的可发布 APK。
    printf '%s' "$artifacts" | jq -r \
      '.artifacts[] | select(.name == "manager") | "\(.name)\t\(.archive_download_url)"'
  else
    printf '%s' "$artifacts" | jq -r --arg needle "$KSUM" \
      '.artifacts[] | select((.name | ascii_downcase) | contains($needle)) | "\(.name)\t\(.archive_download_url)"'
  fi
}

# 仿 BakaSU_CI：正式通道只认官方默认分支最新上传（push 或手动触发）的 Manager 构建，
# 并以下载到的 APK 文件名实测 versionCode 命名，确保包名与包内容严格一致
# 注意：runs 列表 API 的排序/缓存在部分仓库不可靠（可能漏掉最新构建），
# 而 created 日期过滤参数走可靠查询路径，因此按日期窗口从今天往回推进检索
RUNS_BASE="https://api.github.com/repos/$REPO/actions/workflows/$FILENAME/runs?status=success"
CAND_FILE=$(mktemp)
TODAY=$(date -u +%Y-%m-%d)

for DAYS in 0 7 30 90 365; do
  if [ "$DAYS" -eq 0 ]; then
    FROM="$TODAY"
  else
    FROM=$(date -u -d "today - $DAYS days" +%Y-%m-%d)
  fi
  echo "检索 $FROM ~ $TODAY 期间的 Manager 构建..."
  for PAGE in 1 2 3; do
    RUNS=""
    for ATTEMPT in 1 2 3; do
      RUNS=$(curl -s --fail --max-time 30 -H "Authorization: token ${GH_TOKEN}" \
        "$RUNS_BASE&created=$FROM..$TODAY&per_page=30&page=$PAGE") && [ -n "$RUNS" ] && break
      echo "查询构建列表失败，重试 ($ATTEMPT/3)..."
      RUNS=""
      sleep 3
    done
    RUN_COUNT=$(printf '%s' "$RUNS" | jq '.workflow_runs | length')
    if [ "$RUN_COUNT" -eq 0 ]; then
      break
    fi
    for INDEX in $(seq 0 $((RUN_COUNT - 1))); do
      BUILD_ID=$(printf '%s' "$RUNS" | jq -r ".workflow_runs[$INDEX].id")
      CAND_SHA=$(printf '%s' "$RUNS" | jq -r ".workflow_runs[$INDEX].head_sha")
      CAND_BRANCH=$(printf '%s' "$RUNS" | jq -r ".workflow_runs[$INDEX].head_branch")
      EVENT=$(printf '%s' "$RUNS" | jq -r ".workflow_runs[$INDEX].event")
      CREATED=$(printf '%s' "$RUNS" | jq -r ".workflow_runs[$INDEX].created_at")
      # 正式：只认官方默认分支上传的构建，跳过 PR / 其他分支
      # 最新：接受任意分支的构建（跳过 PR），再按版本与 HEAD 匹配排序
      if [ "$PIN_MODE" = "head" ]; then
        if [ "$EVENT" != "push" ] && [ "$EVENT" != "workflow_dispatch" ]; then
          echo "跳过构建 $BUILD_ID ($CAND_BRANCH/$EVENT): 非 push/手动触发构建"
          continue
        fi
      elif [ "$CAND_BRANCH" != "$EXPECTED_BRANCH" ] || { [ "$EVENT" != "push" ] && [ "$EVENT" != "workflow_dispatch" ]; }; then
        echo "跳过构建 $BUILD_ID ($CAND_BRANCH/$EVENT): 非官方 $EXPECTED_BRANCH 分支构建"
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' "$CREATED" "$BUILD_ID" "$CAND_SHA" "$CAND_BRANCH" >> "$CAND_FILE"
    done
  done
  if [ -s "$CAND_FILE" ]; then
    break
  fi
done

if [ ! -s "$CAND_FILE" ]; then
  rm -f "$CAND_FILE"
  echo "未找到可用的 Manager 构建。"
  exit 1
fi

# 去重后排序：
#   正式 → 默认分支构建按时间倒序
#   最新 → SukiSU/BakaSU 优先「版本与 HEAD 一致」的构建，其次默认分支，最后其他分支
#          FinaSU 直接按构建时间倒序（最新 build-manager.yml 产物即目标）
CAND_UNIQ=$(mktemp)
sort -u -t$'\t' -k2,2 "$CAND_FILE" > "$CAND_UNIQ"
rm -f "$CAND_FILE"

PREF_SHA=""
if [ "$PIN_MODE" = "head" ] && [ -n "$HEAD_VERSION" ]; then
  while IFS=$'\t' read -r CREATED BUILD_ID CAND_SHA CAND_BRANCH; do
    if [ "$CAND_SHA" = "$HEAD_SHA" ]; then
      PREF_SHA="$CAND_SHA"
      break
    fi
    git -C KernelSU cat-file -e "${CAND_SHA}^{commit}" 2>/dev/null \
      || git -C KernelSU fetch -q origin "$CAND_SHA" 2>/dev/null \
      || continue
    CAND_COUNT=$(git -C KernelSU rev-list --count "$CAND_SHA" 2>/dev/null || echo "")
    [ -n "$CAND_COUNT" ] || continue
    if [ "$(ksu_version_of "$VARIANT" "$CAND_COUNT")" = "$HEAD_VERSION" ]; then
      PREF_SHA="$CAND_SHA"
      break
    fi
  done < <(sort -t$'\t' -k1,1r "$CAND_UNIQ" | head -n 40)
  if [ -n "$PREF_SHA" ]; then
    echo "优先选择与 HEAD 版本 $HEAD_VERSION 一致的构建提交 ${PREF_SHA:0:8}"
  fi
fi

ORDERED_FILE=$(mktemp)
# 候选行格式：创建时间 \t 构建ID \t 提交 \t 分支（优先级在 awk 里补在第 1 列）
if [ "$VARIANT" == "FinaSU" ] && [ "$PIN_MODE" = "head" ]; then
  sort -t$'\t' -k1,1r "$CAND_UNIQ" \
    | awk -F'\t' '{ print "0\t" $0 }' > "$ORDERED_FILE"
else
  sort -t$'\t' -k1,1r "$CAND_UNIQ" \
    | awk -F'\t' -v pref="$PREF_SHA" -v br="$EXPECTED_BRANCH" \
        '{ p = (pref != "" && $3 == pref) ? 0 : ($4 == br ? 1 : 2); print p "\t" $0 }' \
    | sort -t$'\t' -k1,1n -k2,2r > "$ORDERED_FILE"
fi
rm -f "$CAND_UNIQ"

CAND_COUNT=$(wc -l < "$ORDERED_FILE")
echo "共找到 $CAND_COUNT 个可用构建，按优先级逐个尝试（以 APK 文件名实测版本）..."

MANAGER_VERSION=""
MANAGER_BUILD_ID=""
MANAGER_HEAD_SHA=""
MANAGER_BRANCH=""
while IFS=$'\t' read -r PRIO CREATED BUILD_ID CAND_SHA CAND_BRANCH; do
  ARTIFACTS=$(curl -s -H "Authorization: token ${GH_TOKEN}" \
    "https://api.github.com/repos/$REPO/actions/runs/$BUILD_ID/artifacts")
  CANDIDATE_LIST=$(get_manager_artifacts "$ARTIFACTS")
  if [ -z "$CANDIDATE_LIST" ]; then
    echo "跳过构建 $BUILD_ID ($CAND_BRANCH, $CREATED): 未找到包含 '$KSUM' 的产物"
    continue
  fi

  echo "下载构建 $BUILD_ID ($CAND_BRANCH, $CREATED, ${CAND_SHA:0:8}) 的产物..."
  rm -rf manager-artifacts
  mkdir -p manager-artifacts
  while IFS=$'\t' read -r NAME URL; do
    SAFE_NAME=$(echo "$NAME" | tr '/ ' '__')
    if ! curl -sL --fail -H "Authorization: token ${GH_TOKEN}" \
      -o "manager-artifacts/$SAFE_NAME.zip" "$URL"; then
      echo "下载 $NAME 失败"
      continue
    fi
    mkdir -p "manager-artifacts/$SAFE_NAME"
    unzip -oq "manager-artifacts/$SAFE_NAME.zip" -d "manager-artifacts/$SAFE_NAME" || echo "解压 $NAME 失败"
    rm -f "manager-artifacts/$SAFE_NAME.zip"
  done <<< "$CANDIDATE_LIST"

  # 从 APK 文件名提取实测 versionCode 作为 artifact 命名
  # 优先 arm64-v8a release（BakaSU 下游只保留这一个 ABI）
  APK_FILE=$(find manager-artifacts -type f -name "*-arm64-v8a-release.apk" | head -n 1)
  if [ -z "$APK_FILE" ]; then
    APK_FILE=$(find manager-artifacts -type f -name "*release.apk" ! -name "*debug*" | head -n 1)
  fi
  if [ -z "$APK_FILE" ]; then
    echo "跳过构建 $BUILD_ID ($CAND_BRANCH, $CREATED): artifact 中无 release APK"
    continue
  fi
  # 先剥离 ABI 段再提取版本，避免 x86_64 的 "_64" 等数字尾巴被误当成 versionCode
  CLEAN_NAME=$(basename "$APK_FILE" | sed -E 's/-(arm64-v8a|armeabi-v7a|armv7|riscv64|x86_64|x86|universal)-release\.apk$/.apk/')
  ACTUAL_VERSION=$(echo "$CLEAN_NAME" | grep -oE '_[0-9]+' | tail -n 1 | tr -d '_')
  if ! [[ "$ACTUAL_VERSION" =~ ^[0-9]+$ ]]; then
    echo "跳过构建 $BUILD_ID ($CAND_BRANCH, $CREATED): 无法从 APK 文件名解析版本 ($(basename "$APK_FILE"))"
    continue
  fi

  MANAGER_VERSION="$ACTUAL_VERSION"
  MANAGER_BUILD_ID="$BUILD_ID"
  MANAGER_HEAD_SHA="$CAND_SHA"
  MANAGER_BRANCH="$CAND_BRANCH"
  break
done < "$ORDERED_FILE"
rm -f "$ORDERED_FILE"

if [ -z "$MANAGER_VERSION" ]; then
  echo "未获取到可用的 Manager artifact。"
  exit 1
fi
echo "选择 Manager 构建 $MANAGER_BUILD_ID ($MANAGER_BRANCH, ${MANAGER_HEAD_SHA:0:8}), APK 实测版本 $MANAGER_VERSION"

if [ "$VARIANT" == "FinaSU" ]; then
  # 最新通道的 FinaSU 管理器来自 CI artifact，签名证书需从该 APK 提取，
  # 供内核第二信任槽对齐。
  CERT_INFO=$(python3 "$GITHUB_WORKSPACE/scripts/finasu_compat/extract_manager_cert.py" "$APK_FILE" | head -n1)
  if [ -z "$CERT_INFO" ]; then
    echo "::error::未能从 FinaSU 管理器 APK 提取签名证书"
    exit 1
  fi
  CERT_SIZE=$(echo "$CERT_INFO" | awk '{print $1}')
  CERT_HASH=$(echo "$CERT_INFO" | awk '{print $2}')
  echo "管理器签名证书: size=$CERT_SIZE sha256=$CERT_HASH"
  echo "managerCertSize=$CERT_SIZE" >> $GITHUB_OUTPUT
  echo "managerCertHash=$CERT_HASH" >> $GITHUB_OUTPUT
fi

# 内核侧将对齐到该构建的同一提交（BakaSU：直接检出；SukiSU：改写版本来源 REPO_BRANCH），
# 因此对比"该提交对应的 KSU 版本"而非默认分支 HEAD 的版本
PIN_COUNT=$(git -C KernelSU rev-list --count "$MANAGER_HEAD_SHA" 2>/dev/null || echo "")
if [ -n "$PIN_COUNT" ]; then
  PINNED_KSU_VERSION=$(ksu_version_of "$VARIANT" "$PIN_COUNT")
  if [ -n "$PINNED_KSU_VERSION" ]; then
    echo "内核 KSU 版本将对齐构建提交 ${MANAGER_HEAD_SHA:0:8}: $PINNED_KSU_VERSION"
    if [ "$MANAGER_VERSION" != "$PINNED_KSU_VERSION" ]; then
      echo "::warning::Manager 实测版本 $MANAGER_VERSION 与构建提交对应的 KSU 版本 $PINNED_KSU_VERSION 不一致"
    fi
  elif [ -n "${KSU_VERSION:-}" ] && [ "$MANAGER_VERSION" != "$KSU_VERSION" ]; then
    echo "::warning::Manager 实测版本 $MANAGER_VERSION 与内核 KSU 版本 ${KSU_VERSION} 不一致"
  fi
elif [ -n "${KSU_VERSION:-}" ] && [ "$MANAGER_VERSION" != "$KSU_VERSION" ]; then
  echo "::warning::Manager 实测版本 $MANAGER_VERSION 与内核 KSU 版本 ${KSU_VERSION} 不一致（无法计算构建提交对应的版本）"
fi

echo "MANAGER_VERSION=$MANAGER_VERSION" >> $GITHUB_ENV
echo "managerVer=$MANAGER_VERSION" >> $GITHUB_OUTPUT

# 内核提交锁定策略：
#   正式 → 锁定该构建提交（版本与管理器严格一致）
#   最新 → SukiSU/BakaSU 锁定选择时刻的默认分支 HEAD；FinaSU 锁定产出管理器的构建提交
if [ "$PIN_MODE" = "head" ] && [ -n "$HEAD_SHA" ] && [ "$VARIANT" != "FinaSU" ]; then
  if [ -n "$HEAD_VERSION" ] && [ "$MANAGER_VERSION" != "$HEAD_VERSION" ]; then
    echo "::warning::最新通道：未找到与 $EXPECTED_BRANCH HEAD 版本 $HEAD_VERSION 一致的管理器，回退到 $MANAGER_VERSION"
  fi
  echo "ksuCommit=$HEAD_SHA" >> $GITHUB_OUTPUT
  echo "ksuBranch=$EXPECTED_BRANCH" >> $GITHUB_OUTPUT
else
  echo "ksuCommit=$MANAGER_HEAD_SHA" >> $GITHUB_OUTPUT
  echo "ksuBranch=$MANAGER_BRANCH" >> $GITHUB_OUTPUT
fi

if [ "$VARIANT" == "BakaSU" ]; then
  echo "仅保留 BakaSU arm64-v8a release 管理器..."
  find manager-artifacts -type f -name "*.apk" ! -name "*-arm64-v8a-release.apk" -delete
  find manager-artifacts -type f -name "*debug*.apk" -delete
  if ! find manager-artifacts -type f -name "*-arm64-v8a-release.apk" | grep -q .; then
    echo "未找到 BakaSU arm64-v8a release 管理器。"
    exit 1
  fi
  find manager-artifacts -type f -name "*.apk" -print
fi

echo "MANAGER_FETCH_OK=true" >> $GITHUB_ENV
