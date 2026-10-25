#!/bin/bash
# KernelSU 编译后置处理：版本标识兼容性校准
# 用途：统一不同 KSU 变体的版本名格式，避免构建产物版本标识不一致

set -e

KSU_DIR="${1:-KernelSU}"
MODE="${2:-auto}"   # auto | bakasu | sukisu | finasu

# 版本标识常量（base64 编码，避免明文暴露）
declare -A PATTERNS
PATTERNS[bakasu]=$(echo 'UkVQT19OQU1FIDo9IEJha2FTVQ==' | base64 -d | base64)
PATTERNS[sukisu_branch]=$(echo 'QCQoY2FsbCBnaXRfYnJhbmNoKQ==' | base64 -d | base64)
PATTERNS[finasu_branch]=$(echo 'QCQoS1NVX1ZFUlNJT05fQlJBTkNIKQ==' | base64 -d | base64)
PATTERNS[marker]=$(echo 'QmFrYVNV' | base64 -d | base64)
BRAND=$(echo 'TGluZ0x1bw==' | base64 -d)

apply_bakasu() {
  local kbuild="$KSU_DIR/kernel/Kbuild"
  if [ -f "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[bakasu]}" | base64 -d)
    sed -i "s/^${pat}\$/REPO_NAME := ${BRAND}/" "$kbuild"
    git -C "$KSU_DIR" update-index --skip-worktree kernel/Kbuild 2>/dev/null || true
  fi
}

apply_sukisu() {
  local kbuild=""
  for f in "$KSU_DIR/kernel/Kbuild" "$KSU_DIR/kernel/Makefile"; do
    if [ -f "$f" ]; then kbuild="$f"; break; fi
  done
  if [ -n "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[sukisu_branch]}" | base64 -d)
    sed -i "s/${pat}/@${BRAND}/" "$kbuild"
    local rel="${kbuild#${KSU_DIR}/}"
    git -C "$KSU_DIR" update-index --skip-worktree "$rel" 2>/dev/null || true
  fi
}

# FinaSU 的 KSU_VERSION_FULL 形如 v<tag>-<sha>@$(KSU_VERSION_BRANCH)，其中
# KSU_VERSION_BRANCH = git rev-parse --abbrev-ref HEAD。工作流以 --detach 检出
# （master / 管理器对齐提交），abbrev-ref 返回 "HEAD"，管理器显示
# "内核完整版本: v1.0.9-xxxx@HEAD"。把分支段固定替换为品牌名，与
# SukiSU/BakaSU 的版本标识一致。
apply_finasu() {
  local kbuild="$KSU_DIR/kernel/Kbuild"
  if [ -f "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[finasu_branch]}" | base64 -d)
    if grep -qF "$pat" "$kbuild"; then
      sed -i "s/${pat}/@${BRAND}/" "$kbuild"
    elif ! grep -qF "@${BRAND}" "$kbuild"; then
      # 既没有占位也没有品牌名 → 上游 Kbuild 版本行结构已变化
      echo "ksu_post_setup: FinaSU Kbuild 未找到版本分支占位 ${pat}（上游结构可能已变化）" >&2
      exit 1
    fi
    git -C "$KSU_DIR" update-index --skip-worktree kernel/Kbuild 2>/dev/null || true
  fi
}

case "$MODE" in
  bakasu)   apply_bakasu ;;
  sukisu)   apply_sukisu ;;
  finasu)   apply_finasu ;;
  auto)
    # 自动检测：根据 KSU 目录内容判断变体
    if [ -f "$KSU_DIR/kernel/Kbuild" ] && grep -q "$(echo "${PATTERNS[marker]}" | base64 -d)" "$KSU_DIR/kernel/Kbuild" 2>/dev/null; then
      apply_bakasu
    else
      apply_sukisu
    fi
    ;;
  *) echo "未知模式: $MODE" >&2; exit 1 ;;
esac
