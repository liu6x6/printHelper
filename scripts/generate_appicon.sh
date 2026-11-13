#!/bin/bash
# ============================================================
# generate_appicon.sh — 一键生成 / 替换 AppIcon 图标集（通用版）
#
# 用法:
#   ./scripts/generate_appicon.sh                     # 当前脚本所在项目，图标默认 ~/123
#   ./scripts/generate_appicon.sh /path/to/MyProject  # 指定项目路径（自动找 xcassets/AppIcon）
#   ./scripts/generate_appicon.sh /path/to/MyProject /path/to/icons
#   ./scripts/generate_appicon.sh . ~/123             # 当前目录作为项目
#
# 自动定位规则:
#   1. 递归查找项目下所有 *.xcassets（跳过 .git/build/DerivedData/Pods 等）
#   2. 优先使用已包含 AppIcon.appiconset 的 catalog
#   3. 有 catalog 但没有 AppIcon → 在第一个 catalog 里新建 AppIcon.appiconset
#   4. 完全没有 catalog → 在项目根新建 Assets.xcassets/AppIcon.appiconset
#
# 图标源:
#   默认 ~/123；命名约定 Icon-<pt>[@<scale>x].png（如 Icon-20@3x.png）
#   也可传单个大图（如 1024.png），自动缩放全部尺寸
#   缺某个尺寸时自动用最大图 sips 缩放补齐
#
# 依赖: macOS 自带 sips，无需第三方工具。重复运行即“替换”。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT="${1:-$PROJECT_ROOT}"
ICONS="${2:-$HOME/123}"

command -v sips >/dev/null 2>&1 || { echo "错误: 需要 macOS 自带的 sips"; exit 1; }
[[ -d "$PROJECT" ]] || { echo "错误: 项目目录不存在: $PROJECT"; exit 1; }
PROJECT="$(cd "$PROJECT" && pwd)"

# ---------- 1. 自动定位 xcassets / AppIcon ----------
CATALOGS=$(find "$PROJECT" -type d -name "*.xcassets" \
    -not -path "*/.git/*" -not -path "*/build/*" -not -path "*/DerivedData/*" \
    -not -path "*/Pods/*" -not -path "*/.build/*" -not -path "*/node_modules/*" \
    2>/dev/null | sort || true)

ASSETS=""
APPICON=""
# 2. 优先：已含 AppIcon.appiconset 的 catalog
while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if [[ -d "$d/AppIcon.appiconset" ]]; then
        ASSETS="$d"; APPICON="$d/AppIcon.appiconset"
        echo "定位到已有 AppIcon: $APPICON"
        break
    fi
done <<< "$CATALOGS"

if [[ -z "$ASSETS" ]]; then
    first=$(head -1 <<< "$CATALOGS")
    if [[ -n "$first" ]]; then
        # 3. 有 catalog 没 AppIcon → 补建
        ASSETS="$first"; APPICON="$first/AppIcon.appiconset"
        echo "已有 catalog 无 AppIcon，新建: $APPICON"
    else
        # 4. 完全没有 → 新建 Assets.xcassets
        ASSETS="$PROJECT/Assets.xcassets"; APPICON="$ASSETS/AppIcon.appiconset"
        echo "未找到 xcassets，新建: $ASSETS"
    fi
fi
mkdir -p "$APPICON"

# ---------- 2. 确定 master 大图（用于补齐缺失尺寸） ----------
MASTER=""
if [[ -f "$ICONS" ]]; then
    MASTER="$ICONS"
elif [[ -d "$ICONS" ]]; then
    if [[ -f "$ICONS/Icon-1024.png" ]]; then
        MASTER="$ICONS/Icon-1024.png"
    else
        best=0
        for f in "$ICONS"/*.png "$ICONS"/*.jpg "$ICONS"/*.jpeg; do
            [[ -f "$f" ]] || continue
            w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
            [[ -n "$w" ]] || continue
            if (( w > best )); then best=$w; MASTER="$f"; fi
        done
    fi
else
    echo "错误: 图标源不存在: $ICONS"; exit 1
fi
[[ -n "$MASTER" && -f "$MASTER" ]] || { echo "错误: 找不到可用源图: $ICONS"; exit 1; }
echo "项目: $PROJECT"
echo "图标源: $ICONS (master: $(basename "$MASTER"))"

# ---------- 3. 清空旧图标（保证“替换”干净） ----------
rm -f "$APPICON"/*.png

# ---------- 4. 条目表: idiom|pt|scale|文件名（iOS 全套 + macOS 全套） ----------
ENTRIES=(
    "iphone|20|2|Icon-20@2x.png"
    "iphone|20|3|Icon-20@3x.png"
    "iphone|29|2|Icon-29@2x.png"
    "iphone|29|3|Icon-29@3x.png"
    "iphone|40|2|Icon-40@2x.png"
    "iphone|40|3|Icon-40@3x.png"
    "iphone|60|2|Icon-60@2x.png"
    "iphone|60|3|Icon-60@3x.png"
    "ipad|20|1|Icon-20.png"
    "ipad|20|2|Icon-20@2x.png"
    "ipad|29|1|Icon-29.png"
    "ipad|29|2|Icon-29@2x.png"
    "ipad|40|1|Icon-40.png"
    "ipad|40|2|Icon-40@2x.png"
    "ipad|76|1|Icon-76.png"
    "ipad|76|2|Icon-76@2x.png"
    "ipad|83.5|2|Icon-83.5@2x.png"
    "ios-marketing|1024|1|Icon-1024.png"
    "mac|16|1|Icon-16.png"
    "mac|16|2|Icon-16@2x.png"
    "mac|32|1|Icon-32.png"
    "mac|32|2|Icon-32@2x.png"
    "mac|128|1|Icon-128.png"
    "mac|128|2|Icon-128@2x.png"
    "mac|256|1|Icon-256.png"
    "mac|256|2|Icon-256@2x.png"
    "mac|512|1|Icon-512.png"
    "mac|512|2|Icon-512@2x.png"
)

# ---------- 5. 逐条拷贝 / 缩放，并累积 Contents.json ----------
json_images=""
copied=0; resized=0
for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r idiom pt scale filename <<< "$entry"
    px=$(awk "BEGIN{printf \"%d\", $pt * $scale}")
    src="$ICONS/$filename"
    if [[ -f "$src" ]]; then
        cp "$src" "$APPICON/$filename"
        copied=$((copied + 1))
    else
        sips -z "$px" "$px" "$MASTER" --out "$APPICON/$filename" >/dev/null
        resized=$((resized + 1))
    fi
    [[ -n "$json_images" ]] && json_images+=","
    json_images+=$(cat <<EOF

    {
      "filename" : "$filename",
      "idiom" : "$idiom",
      "scale" : "${scale}x",
      "size" : "${pt}x${pt}"
    }
EOF
)
done

cat > "$APPICON/Contents.json" <<EOF
{
  "images" : [$json_images
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# ---------- 6. catalog 根 Contents.json ----------
if [[ ! -f "$ASSETS/Contents.json" ]]; then
    cat > "$ASSETS/Contents.json" <<EOF
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
fi

echo "完成: $APPICON"
echo "  直接拷贝 $copied 个, 缩放补齐 $resized 个, 共 ${#ENTRIES[@]} 个尺寸"
echo "提示: 确保 build 设置含 ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon，且 catalog 已加入 target sources"