#!/bin/bash
# ============================================================
# generate_appicon.sh — 一键生成 / 替换 AppIcon 图标集
#
# 用法:
#   ./scripts/generate_appicon.sh                     # 默认从 ~/123 生成
#   ./scripts/generate_appicon.sh /path/to/icons      # 指定图标目录
#   ./scripts/generate_appicon.sh /path/to/1024.png   # 单张大图（自动缩放全部尺寸）
#   ./scripts/generate_appicon.sh ~/123 /path/to/Media.xcassets
#
# 源目录命名约定: Icon-<pt>[@<scale>x].png（如 Icon-20@3x.png、Icon-83.5@2x.png）
# 缺少某个尺寸时，自动用最大图（Icon-1024.png 或目录中最大 PNG）sips 缩放补齐。
# 依赖: macOS 自带 sips，无需安装任何第三方工具。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC="${1:-$HOME/123}"
ASSETS="${2:-$PROJECT_ROOT/PrintHelper/Media.xcassets}"
APPICON="$ASSETS/AppIcon.appiconset"

command -v sips >/dev/null 2>&1 || { echo "错误: 需要 macOS 自带的 sips"; exit 1; }

# ---------- 1. 确定 master 大图（用于补齐缺失尺寸） ----------
MASTER=""
if [[ -f "$SRC" ]]; then
    MASTER="$SRC"
elif [[ -d "$SRC" ]]; then
    if [[ -f "$SRC/Icon-1024.png" ]]; then
        MASTER="$SRC/Icon-1024.png"
    else
        best=0
        for f in "$SRC"/*.png "$SRC"/*.jpg "$SRC"/*.jpeg; do
            [[ -f "$f" ]] || continue
            w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
            [[ -n "$w" ]] || continue
            if (( w > best )); then best=$w; MASTER="$f"; fi
        done
    fi
else
    echo "错误: 源不存在: $SRC"; exit 1
fi
[[ -n "$MASTER" && -f "$MASTER" ]] || { echo "错误: 找不到可用源图: $SRC"; exit 1; }
echo "源: $SRC"
echo "master: $MASTER"

# ---------- 2. 清空旧图标（保证“替换”干净） ----------
mkdir -p "$APPICON"
rm -f "$APPICON"/*.png

# ---------- 3. 条目表: idiom|pt|scale|文件名 ----------
# iOS 全套 + macOS 全套（Xcode 通用 appiconset）
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

# ---------- 4. 逐条拷贝 / 缩放，并累积 Contents.json ----------
json_images=""
copied=0; resized=0
for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r idiom pt scale filename <<< "$entry"
    px=$(awk "BEGIN{printf \"%d\", $pt * $scale}")
    src="$SRC/$filename"
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

# ---------- 5. catalog 根 Contents.json ----------
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
echo "提示: 若首次添加 catalog，请确认 project.yml 含 ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon，然后 xcodegen generate"