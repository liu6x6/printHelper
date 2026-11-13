<div align="center">

<img src="icon.svg" width="160" alt="PrintHelper Icon"/>

# PrintHelper

**把作业图片排版到 A4，切割省纸，导出 PDF 打印** 📄 ✂️ 🖨️

老师发的作业图片尺寸随机？直接打印放大浪费纸？
PrintHelper 帮你把图片按合适比例排到标准 A4 页面上，自由调整、横向/纵向切割，一页都不浪费。

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20iOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0071e3)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## ✨ 功能

### macOS —— Word 式自由画布

- 📥 **三种导入方式**：Finder 拖拽 / 菜单导入（⌘O）/ 粘贴截图（⌘V）
- 🖱️ 图片默认铺满页宽，**自由拖动位置、拖角点缩放**，可跨页拖拽
- 📑 图片不跨页：拖出页底整张自动挪到下一页，**自动扩页**
- 📜 超高长图**自动按页边界切分**续页，字不小、最省纸
- ✂️ **切割图片**：双击图片，拖一条切割线切成两段独立图片
  - 横向（上下分）/ 纵向（左右分），像素级无损
  - **N 等分**（2–8 段）一键均分
  - 切掉不好看的边角，剩下的继续排版
- 🔄 顺时针旋转 90°；🧲 拖拽对齐吸附 + 参考线；工具栏精确百分比输入
- ⌫ Delete 键删除；⌘Z / ⇧⌘Z 撤销重做（覆盖切割/旋转）
- 📦 **工程保存/打开**（.phdoc）：⌘S 保存完整可编辑状态，⌘O 打开继续编辑
- 🖨️ **⌘P 直接打印**；📤 ⌘E / 文件菜单导出标准 A4 PDF（300 DPI）

### iOS —— 单列流式排版

- 🖼️ 相册**一次性多选导入**，按 A4 宽度自动排列
- ↕️ 拖拽调序、滑杆缩放单张宽度（点百分比可精确输入）、删除、旋转
- ✂️ 同样支持横向/纵向切割、N 等分、超高图自动切分
- 📦 工程保存/打开（.phdoc，存到「文件」App）
- 🖨️ AirPrint 直接打印
- 📤 导出 **PDF / 每页 PNG / 长图**，系统分享面板（微信 / AirDrop…）

### 省纸示例

> 3 张 60% 大小的图片原本要 3 张纸 → 每张横切一刀 → **2 张纸搞定** ✌️

## 🚀 快速开始

### 环境要求

- macOS 14+，Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

### 构建运行

```bash
git clone https://github.com/liu6x6/printHelper.git
cd printHelper
xcodegen generate          # 生成 PrintHelper.xcodeproj
open PrintHelper.xcodeproj # 选 PrintHelper scheme → My Mac 或 iOS 模拟器运行
```

命令行构建：

```bash
# macOS
xcodebuild -project PrintHelper.xcodeproj -scheme PrintHelper \
  -destination 'platform=macOS' build

# iOS 模拟器
xcodebuild -project PrintHelper.xcodeproj -scheme PrintHelper \
  -destination 'generic/platform=iOS Simulator' build
```

> 💡 `.xcodeproj` 由 XcodeGen 生成，不入库；改完 `project.yml` 重新 `xcodegen generate` 即可。

## 🎨 App 图标（一键生成 / 替换，通用脚本）

只需指定**项目路径**，脚本自动定位/创建图标集（仅依赖 macOS 自带 `sips`）：

```bash
./scripts/generate_appicon.sh                     # 本项目，图标默认 ~/123
./scripts/generate_appicon.sh /path/to/MyProject  # 任意项目，自动找 xcassets/AppIcon
./scripts/generate_appicon.sh . /path/to/icons    # 指定图标源目录
./scripts/generate_appicon.sh . /path/to/1024.png # 单张大图，自动缩放全部尺寸
```

**自动定位规则**：
1. 递归查找项目下所有 `*.xcassets`（跳过 .git/build/DerivedData/Pods 等）
2. 优先使用已含 `AppIcon.appiconset` 的 catalog
3. 有 catalog 但没 AppIcon → 在其中新建 `AppIcon.appiconset`
4. 完全没有 catalog → 在项目根新建 `Assets.xcassets/AppIcon.appiconset`

**图标源**：默认 `~/123`，命名约定 `Icon-<pt>[@<scale>x].png`（如 `Icon-20@3x.png`、`Icon-83.5@2x.png`）；覆盖 iOS 全套 + macOS 全套共 28 个尺寸，缺尺寸自动用最大图缩放补齐；重复运行即“替换”。

> 脚本只更新 catalog；确保 build 设置含 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 且 catalog 已加入 target sources（本项目 `project.yml` 已配好），重新构建即生效。

## 🧪 测试

核心引擎（排版 / 切割 / 导出）不依赖 UI，可单独编译验证：

```bash
swiftc PrintHelper/Core/*.swift Tests/main.swift -o /tmp/ph_core_test && /tmp/ph_core_test
```

**58 项断言**覆盖：

| 类别 | 内容 |
|------|------|
| 排版 | 流式分页、free 整张换页、跨页拖回、超高图自动切分 |
| 切割 | 横切/纵切/N 等分像素无损、省纸场景、视觉比例保持 |
| 编辑 | 撤销/重做（含切割/旋转/打开工程）、调序、批量删除、资源回收 |
| 工程 | .phdoc 保存/打开往返一致（位置/缩放/切割结果/像素） |
| 导出 | A4 PDF 页数/尺寸、300 DPI PNG、长图拼接、**方向正立回归** |

## 🏗️ 项目结构

```
PrintHelper/
├── Core/                    # 双平台共享引擎（无 UI 依赖）
│   ├── Geometry.swift       # A4 常量 / 页边距
│   ├── ImageAsset.swift     # 原图数据 + 懒解码 + 缩略图
│   ├── PrintDocument.swift  # 值类型文档模型（快照 = 撤销单元）
│   ├── ImageCutter.swift    # 像素级横/纵切割（无损 PNG）
│   ├── LayoutEngine.swift   # free / flow 排版 + 换页规范化
│   ├── PDFRenderer.swift    # A4 PDF / 每页 PNG / 长图（300/150 DPI）
│   ├── ProjectFile.swift    # .phdoc 工程归档（JSON 清单 + 原图）
│   └── EditorModel.swift    # 编辑动作 + 撤销重做 + 导入自动切分
├── Views/
│   ├── Shared/              # 页面预览、切割面板、PDF 导出文档
│   ├── macOS/               # 统一画布编辑器 + 菜单命令
│   └── iOS/                 # 预览 + 排序调整 + 分享
└── PrintHelperApp.swift
Tests/main.swift             # 核心逻辑测试（58 项断言）
project.yml                  # XcodeGen 配置（单一 Multiplatform target）
REQUIREMENTS.md              # 完整需求文档（v1.2）
```

**架构要点**

- 单一 Multiplatform target，macOS / iOS 共享全部核心代码
- 文档为值类型，整文档快照实现撤销/重做；图片资源引用共享，快照成本极低
- 屏幕显示用缩略图，导出才用原图（50+ 张照片不卡顿）
- 完全离线、无账号、图片不上传任何服务器

## 🗺️ Roadmap

M1 / M2 / M3 全部完成 ✅

- [x] 工程文件保存（.phdoc 可编辑文档，双平台）
- [x] 对齐吸附 / 参考线
- [x] 精确比例输入
- [x] 应用内直接打印（macOS 打印面板 / AirPrint）
- [x] 图片旋转、长图导出、N 等分切割

后续想法：最近打开列表、任意角度旋转、文字标注（姓名/日期）。

详见 [REQUIREMENTS.md](REQUIREMENTS.md)。

## 📄 License

[MIT](LICENSE)