# PrintHelper

把老师发的作业图片排版到标准 A4 页面，自由移动/缩放/横向切割，导出 PDF 打印，省纸。

需求文档见 [REQUIREMENTS.md](REQUIREMENTS.md)（v1.1，已闭环）。

## 功能（M1 + M2 已实现）

**macOS**（Word 式自由画布）
- 新建 A4 文档，拖拽文件 / ⌘O 导入 / ⌘V 粘贴图片
- 图片默认铺满页宽，可拖动位置、拖角点缩放
- 图片不跨页：拖出页底整张自动挪到下一页，自动扩页
- 超高长图自动按页边界切分续页
- 双击图片或工具栏 ✂️：拖一条水平切割线，切成上下两段独立图片
- ⌘Z / ⇧⌘Z 撤销重做（覆盖切割）
- ⌘E 导出标准 A4 PDF（300 DPI）

**iOS**（单列流式排版）
- 相册批量导入，按 A4 宽度自动排列，放不下整张换页
- 拖拽调序、滑杆缩放单张宽度、删除、切割
- 超高长图自动切分
- 导出 PDF / 每页 PNG，系统分享面板

## 构建

需要 Xcode 16+（开发环境 Xcode 27.2）与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
xcodegen generate          # 生成 PrintHelper.xcodeproj
open PrintHelper.xcodeproj # 选 PrintHelper scheme，目标 My Mac 或 iOS 模拟器
```

命令行构建：

```bash
xcodebuild -project PrintHelper.xcodeproj -scheme PrintHelper -destination 'platform=macOS' build
xcodebuild -project PrintHelper.xcodeproj -scheme PrintHelper -destination 'generic/platform=iOS Simulator' build
```

## 核心逻辑测试

核心引擎（排版/切割/PDF）不依赖 UI，可单独编译验证：

```bash
swiftc PrintHelper/Core/*.swift Tests/main.swift -o /tmp/ph_core_test && /tmp/ph_core_test
```

25 项断言覆盖：流式分页、省纸切割场景、像素无损切割、超高图自动切分、
free 模式整张换页、撤销/重做、调序/批量删除、A4 PDF / 300DPI PNG 导出。

## 结构

```
PrintHelper/
  Core/                 # 双平台共享，无 UI 依赖
    Geometry.swift      # A4 常量 / 页边距
    ImageAsset.swift    # 原图数据 + 懒解码 + 缩略图
    PrintDocument.swift # 值类型文档模型（快照 = 撤销单元）
    ImageCutter.swift   # 像素级横向切割（无损 PNG）
    LayoutEngine.swift  # free / flow 排版 + 整张换页规范化
    PDFRenderer.swift   # A4 PDF / 每页 PNG（300 DPI）
    EditorModel.swift   # 编辑动作 + 撤销重做 + 导入自动切分
  Views/
    Shared/             # 页面预览、切割面板、PDF 导出文档
    macOS/              # 自由画布编辑器
    iOS/                # 预览 + 排序调整
Tests/main.swift        # 核心逻辑冒烟测试
project.yml             # XcodeGen 配置（单一 Multiplatform target）
```

## 后续（M3）

工程文件保存、对齐吸附、精确比例输入、应用内打印、旋转、长图导出、N 等分切割。