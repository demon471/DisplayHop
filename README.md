# DisplayHop / 屏跃

菜单栏窗口管理小工具：一键把当前聚焦的窗口移动到下一个/上一个显示器，类似 Wins。

- 中文名：**屏跃**（系统语言为中文时显示，对应英文 DisplayHop）
- **支持中英双语**：开发语言为 zh-Hans，通过 String Catalog（`Localizable.xcstrings`）提供英文翻译，
  App 名称、菜单、设置、弹窗全部跟随系统语言

## 功能

- **移动到下一屏 / 上一屏**：全局快捷键，默认 `⌃⌥→` / `⌃⌥←`（Wins 风格）
- **自定义快捷键**：设置窗口内录制，冲突检测，自动保存
- **保持相对位置**：窗口跨屏后保持在源屏幕中的相对位置，并夹紧到目标屏幕可见区域（不会跑到菜单栏或 Dock 底下）
- **边界处理**：全屏窗口移动后**恢复全屏状态**（先退出→移动→再进入）、最小化窗口先还原、单屏时忽略、多屏按系统"显示器排列"方向导航并支持回绕
- **图标可分别显示/隐藏**：设置 → 通用 →「显示菜单栏图标」「显示程序坞图标」两个独立开关。
  Dock 图标点击即可打开设置；两个都关掉时启动会弹提示，可一键恢复
- **设置窗口置顶**：从菜单栏点击"设置…"时自动激活 App 并抢焦（菜单栏应用不会自动激活自身）
- **登录时启动**：基于 SMAppService
- **应用图标**：来自 macosicons.com，按 macOS 规范适配（80.5% squircle、透明四角、10 个尺寸）

## 构建与运行

```bash
xcodegen generate          # 生成 DisplayHop.xcodeproj（项目定义见 project.yml）
open DisplayHop.xcodeproj  # Xcode 中 Cmd+R 运行
```

命令行构建 + 测试：

```bash
xcodebuild -project DisplayHop.xcodeproj -scheme DisplayHop -destination 'platform=macOS' test
```

## 首次运行

1. 启动后系统会弹出辅助功能权限引导（系统设置 > 隐私与安全性 > 辅助功能），勾选 DisplayHop
2. 授权后如快捷键未生效，重新启动 App 一次

## 项目结构

```
DisplayHop/
├── DisplayHop/
│   ├── App/
│   │   ├── DisplayHopApp.swift        # 入口：AppDelegate + 快捷键注册 + 隐藏图标兜底
│   │   ├── MenuBarHost.swift          # 菜单栏：NSStatusItem + NSMenu（含显隐）
│   │   ├── SettingsWindowController.swift # 设置窗口：NSWindow + NSHostingView
│   │   ├── AppState.swift             # 菜单动作与失败反馈（系统提示音）
│   │   └── AppPreferences.swift       # 偏好设置（菜单栏图标显隐）
│   ├── Core/
│   │   ├── DisplayGeometry.swift      # 纯几何计算：屏幕排序/归属判定/坐标映射（可单测）
│   │   ├── DisplayInfo+AppKit.swift   # NSScreen(左下原点) ↔ CG(左上原点) 坐标转换
│   │   ├── WindowController.swift     # AX API 封装 + 辅助功能权限 + WindowControlling 协议
│   │   ├── ScreenNavigator.swift      # 移动编排：聚焦窗口 → 定屏 → 映射 → 写回
│   │   └── LaunchAtLogin.swift        # SMAppService 登录启动
│   ├── Resources/
│   │   ├── Assets.xcassets/           # AppIcon（10 个尺寸）+ AccentColor
│   │   ├── Localizable.xcstrings      # 中英双语字符串目录
│   │   └── InfoPlist.xcstrings        # App 名称本地化（屏跃 / DisplayHop）
│   └── UI/
│       └── SettingsView.swift         # 快捷键 / 通用 设置（TabView + Grouped Form）
├── DisplayHopTests/
│   ├── DisplayGeometryTests.swift     # 12 个几何测试
│   └── ScreenNavigatorTests.swift     # 10 个移动编排测试（Mock AX）
└── tools/
    ├── install.sh                     # 构建 Release 并安装到 /Applications
    ├── check_status_item.swift        # 检查状态栏项是否真的注册/可见
    ├── gen_menubar_icons.swift        # 菜单栏图标候选对照表
    ├── preview_icon_weight.swift      # 图标白色纯度对比
    └── preview_menubar_rendering.swift # 渲染模式对比
```

## 技术说明

- 窗口移动基于**辅助功能 API（AX API）**：`AXUIElementCopyAttributeValue` 读取 `kAXPositionAttribute`/`kAXSizeAttribute`，计算后写回 `kAXPositionAttribute`
- 全局快捷键使用 [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（v3，含录制控件与持久化）
- 坐标系：AX 使用主屏幕左上角原点，AppKit 使用左下角原点，`DisplayInfo+AppKit.swift` 统一转换到 CG 空间后再做纯函数计算
- 单元测试不依赖真实显示器与权限：几何计算为纯函数，AX 通过 `WindowControlling` 协议 Mock

## 排查：菜单栏上看不到图标

如果装了 Barbee / Ice / Hidden Bar 这类菜单栏管理工具，它们会把第三方图标移到屏幕外实现"隐藏"。
本 App 的图标可能被自动归到隐藏区段，需要在那个工具里把它拖到可见区域。

用下面的命令确认图标是否真的注册了（`onscreen=1` 表示当前可见）：

```bash
swift tools/check_status_item.swift
```

## 实现中避开的两个 macOS 坑

### 1. `MenuBarExtra(isInserted:)` + Settings 会无限重绘

最初用 SwiftUI 的 `MenuBarExtra(..., isInserted:)` 做图标显隐。点击「设置…」后主线程 100% 死循环，
`sample` 采样栈为：

```
MenuBarExtraHost.requestUpdate → MenuBarExtraController.updateButton
  → NSStatusBarButton.setImage → _adjustLength → 再次 requestUpdate …
```

结论：macOS 15 上 `isInserted` 绑定与 Settings 窗口组合会触发 SwiftUI 无限重绘。
现改为 `NSStatusItem` + `NSMenu` 手动管理（`MenuBarHost`），显隐等价于 `statusItem.isVisible`。

### 2. 设置窗口打不开

SwiftUI `Settings` scene 的呈现依赖内部 action（`showSettingsWindow:`）。
在没有 SwiftUI 菜单栏/responder 链的 NSStatusItem 环境下 `NSApp.sendAction` 找不到处理器，静默失败。
现改为 `NSWindow` + `NSHostingView` 手动托管（`SettingsWindowController`），并显式 `NSApp.activate` 置顶。

## 权限列表图标空白 / 反复要求授权

两个独立原因，都在开发阶段才会遇到：

1. **图标空白**：系统设置通过 LaunchServices 按 bundle id 查图标，
   而 Xcode DerivedData 里的产物没有注册到 LaunchServices，只能显示通用白图标。
   → 装到 `/Applications` 即解决（`tools/install.sh`）。
2. **反复要求授权**：本项目无开发者证书，用 ad-hoc 签名，
   每次重新构建签名都会变，系统当作新 App。
   → 日常使用装到 `/Applications` 后不再重建，权限授一次长期有效。

```bash
./tools/install.sh     # 构建 Release → 安装 → 清理旧注册 → 重置授权 → 启动
```

安装后需在「系统设置 → 隐私与安全性 → 辅助功能」勾选一次**屏跃**。

### 关于 App 名称的语言

Finder 等界面显示的是**文件名**，所以安装后的包名是 `屏跃.app`（脚本会自动清理旧的 `DisplayHop.app`）。
同时保留 `InfoPlist.xcstrings` 的本地化：英文系统下 Finder 会显示 `DisplayHop.app`。

脚本还会注销 Xcode 构建产物在 LaunchServices 里的注册——
否则系统会把这些副本当作额外的同名 App，权限列表里出现多条重复条目（图标为空白）。

### 关于菜单栏图标被"藏起来"

如果装了 Barbee / Ice / Hidden Bar 这类菜单栏管理工具，新出现的图标默认可能被归到隐藏区段，
表现为"图标不见了"。它们通过把状态栏窗口移到屏幕外来实现隐藏，所以：

- 在对应工具里把 **屏跃** 拖到可见区域即可
- 用 `swift tools/check_status_item.swift` 可以确认图标是「可见」还是「被隐藏 / 在屏幕外」

## 发布流程

CI 在**推送版本 tag** 时才构建，普通 push / PR 不触发：

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/build.yml` 会依次：装 xcodegen → 生成工程 → 交叉编译 universal（x86_64 + arm64）→
校验 App 包/架构/版本号 → 打包 DMG → 上传 artifact → 创建 GitHub Release。

也支持在 Actions 页面手动触发（`workflow_dispatch`），填入版本号即可出包。

### 版本号规则

版本号从 tag 提取（`tools/version.sh`）：

| tag | CFBundleShortVersionString | CFBundleVersion |
|---|---|---|
| `v1.2.3` | 1.2.3 | GitHub run number |
| `v2.0.0-beta.1` | 2.0.0 | GitHub run number |
| `v0.1.0-45` | 0.1.0 | 45 |

预发布后缀不会进入版本号（`CFBundleShortVersionString` 只接受数字段），
`CFBundleVersion` 必须是正整数。

### 为什么是 universal 而不是分架构

App 是纯 Swift + 系统框架，无原生依赖，universal 编译零成本；
macOS 通行做法就是发单一 universal 包（Rectangle / Magnet 都是），
用户不用挑架构，Intel Mac 和 M 系列 Mac 都能直接跑。

### 本地出包（不经过 CI）

```bash
./tools/make_dmg.sh /path/to/DisplayHop.app build/dmg 1.2.3
```

### 关于签名

本项目无开发者证书，使用 ad-hoc 签名（"Sign to Run Locally"），因此**无法做 Apple 公证**。
用户首次打开需右键→打开，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/屏跃.app
```

如果以后有 Developer ID 证书，可在 workflow 中追加签名与 `notarytool` 公证步骤。

## 排查手册

App 写入了统一日志，可直接查看：

```bash
log show --predicate 'subsystem == "com.johnbebee.DisplayHop"' --last 5m --style compact
```

设置页的「诊断」标签会实时显示：辅助功能权限状态、当前快捷键、上次操作结果、显示器列表。

### 快捷键按了没反应

按日志分类：

| 日志内容 | 原因 | 处理 |
|---|---|---|
| `辅助功能未授权，无法读取窗口` | 快捷键触发了，但 AX 被拒 | 系统设置 → 隐私与安全性 → 辅助功能，重新勾选屏跃 |
| 没有任何 hotkey 日志 | 快捷键没注册上 | 检查设置页「诊断」里的快捷键是否为空；可能与其他 App 冲突，换一组 |
| `没有聚焦窗口` | 当前没有可移动的窗口 | 先点一下目标窗口 |

### 辅助功能权限反复失效

**这是 ad-hoc 签名的固有问题，不是 bug。**
TCC 把辅助功能授权绑定到 App 的代码签名，而 ad-hoc 签名每次重新构建都会变，
系统会当成一个新 App，旧授权随之失效。

- 日常使用：装到 `/Applications` 后不再重新构建，授权一次即可长期有效
- 开发期：`./tools/install.sh` 会自动 `tccutil reset` 清掉旧条目，重装后重新勾选一次
- 彻底解决：申请 Apple Developer ID 证书并公证（签名稳定，授权不会失效）

### 菜单栏看不到图标

用工具确认（App 本地化后进程名是「屏跃」，脚本已按 bundle id 自动识别）：

```bash
swift tools/check_status_item.swift
```

输出「被隐藏 / 在屏幕外」说明被 Barbee / Ice / Hidden Bar 之类的工具收进了隐藏区段，
在对应工具里拖回可见区域即可。

### 名字显示不对

- Finder 显示的是 **.app 文件名**，不是 CFBundleDisplayName → 打包脚本已把包名设为「屏跃.app」
- 英文系统下会显示 `DisplayHop.app`（由 `InfoPlist.xcstrings` 控制）

## 实现要点

### 全屏窗口跨屏

全屏窗口必须先退出全屏才能改位置，移动完再恢复全屏——
这样窗口会在**目标屏**上全屏，而不是变成普通窗口。
AX 写入是异步生效的，所以退出全屏后要等 `AXFullScreen` 变为 false 再读位置，
否则读到的还是全屏尺寸，映射坐标会算错。

### AX 调用开销

AX 每次属性读取都是一次跨进程 XPC 往返。移动一个窗口原本要 15 次调用，
现在降到 6 次：

| 优化 | 效果 |
|---|---|
| 不读窗口标题（移动用不到） | -1 次 |
| 复用同一个 AXUIElement，不重新查询聚焦窗口 | -5 次 |
| 只重读 position/size，而不是整个窗口快照 | -2 次 |

### 菜单栏 / Dock 双形态

两个开关**相互独立**：

| 菜单栏图标 | 程序坞图标 | 激活策略 | 表现 |
|---|---|---|---|
| 显示 | 显示 | `.regular` | 两个图标都在 |
| 显示 | 隐藏 | `.accessory` | 只有菜单栏图标 |
| 隐藏 | 显示 | `.regular` | 只有 Dock 图标，点击打开设置 |
| 隐藏 | 隐藏 | `.accessory` | 完全隐形，启动时弹提示可恢复 |

实现方式：
- 菜单栏图标 → `NSStatusItem.isVisible`
- 程序坞图标 → 激活策略（`.regular` 有 Dock 图标 / `.accessory` 没有）

用 `.accessory` 时 App 不会被系统自动激活，所以打开设置时需要显式
`NSApp.activate(ignoringOtherApps: true)`。

> 注意：菜单栏图标是否真的可见，还取决于 Barbee / Ice / Hidden Bar 之类的
> 菜单栏管理工具——它们会把第三方图标移到屏幕外（状态项窗口坐标变成负数）。
> 用 `swift tools/check_status_item.swift` 可以区分：
> 坐标为 `0` = 被 App 自己隐藏；坐标为大负数 = 被管理工具藏起来了。
