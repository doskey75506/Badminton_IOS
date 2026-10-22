# 羽毛球俱乐部（iPad）

中文 | [English](README.en.md)

完全离线的羽毛球俱乐部活动 App（iPad / SwiftUI）。不需要网络、不注册账号，所有数据保存在本机。支持多俱乐部、多场地、中英文界面。功能与 [Android 版](https://github.com/doskey75506/Badminton_android) 完全对等（本仓库是其功能完整的移植）。

主要功能：

- **成员管理**：录入姓名、性别、初始积分
- **今晚活动**：一键签到，自动为每个空闲场地生成均衡对阵（单打 1v1 / 双打 2v2）
- **进行中比赛**：中途换人、录入比分（自动更新积分）、作废误生成的比赛
- **四套独立积分榜**：开放单打 / 女子单打 / 开放双打 / 女子双打
- **历史查询**：按时间范围、按球员筛选，查看比分与积分变化
- **数据导出/导入**：zip 备份，通过系统文件选择器完成；导入会**完全覆盖**本机数据（不会合并）
- **中英双语**：随时切换

## 环境要求

- Xcode 16 及以上
- iOS 17.0+，仅 iPad（`TARGETED_DEVICE_FAMILY=2`，bundle id `com.badminton.club`）

## 开发命令

```bash
# 核心逻辑测试（43 个，macOS 主机上直接跑，无需模拟器）
swift test

# 构建 App（必须带 CODE_SIGNING_ALLOWED=NO，仓库未设置 DEVELOPMENT_TEAM）
xcodebuild -project App/Badminton.xcodeproj -scheme Badminton \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
# 产物: build/Build/Products/Debug-iphonesimulator/Badminton.app

# 安装到模拟器（设备 "Badminton iPad"，ID 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8）
xcrun simctl boot 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8
xcrun simctl install 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8 build/Build/Products/Debug-iphonesimulator/Badminton.app
xcrun simctl launch 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8 com.badminton.club
```

仓库没有 lint 步骤（未引入 swiftformat/swiftlint），以 `swift test` + `xcodebuild` 的警告为准。

## 项目结构

- `Package.swift` + `Sources/BadmintonKit/` — SPM 包，纯逻辑（模型、积分、匹配、存储、zip），不依赖 UIKit/SwiftUI，单元测试在 `Tests/BadmintonTests/`（移植自 Android `core` 的三个测试套件 + zip 兼容测试）
- `App/Badminton/` — SwiftUI 界面（六个页面 + 欢迎页，页面切换为普通状态切换）
- `App/Badminton.xcodeproj/` — 手写的 Xcode 16 工程（文件系统同步分组），引用本地 SPM 包 `..`

## 数据

- 以 JSON 存放在 App 沙盒 `Library/Application Support/data/`：`clubs.json` + 每俱乐部 `members.json` / `attendance.json` / `settings.json` / `matches.json`
- 完全离线：不联网、无账号，卸载即删除数据 —— 重要内容请用"导出数据"备份
- 备份/换机：导出为 zip；新设备点"导入数据"选择该文件即可。**导入会完全覆盖本机数据，不会合并**
- 备份格式与 Android 版一致，两端可互相导入

## 语言

菜单中随时切换 中文 / English。
