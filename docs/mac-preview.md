# CleanPhoto Mac 本机试用版

2026-10-27

## 安装与启动

已安装到 `~/Applications/CleanPhoto.app`。可从个人“应用程序”文件夹或 Spotlight 打开。另有 `dist/mac/CleanPhoto-Mac.zip` 本机试用备份。

采用 Mac Catalyst，与 iPhone 共用照片读取、相似分组、收藏、待删确认和整理进度逻辑。当前构建是给这台 Apple 芯片 Mac 使用的本机签名调试版，没有作为公证后的公开安装包发布；项目支持的 Mac 最低系统要求以生成的 Info.plist 为准。

首次启动会显示照片访问引导。由用户点击“允许访问”并决定系统照片权限，代理未代为授权、收藏或删除真实照片。应用读取 Mac 的系统照片图库；iCloud 照片同步由系统照片 App 管理。照片的实际删除仍需用户确认。程序内部整理进度和扫描缓存目前各设备独立。

## 桌面操作

- 窗口最小尺寸 800 × 600，可自由调整大小。
- 逐张整理：K 保留、D 加入待删除；本批结束后统一确认。查看单张时暂停主页整理快捷键，避免误改原位置。
- 单张查看：左右箭头按钮或方向键在当前组内切换，Esc 关闭；鼠标双击及触控板缩放沿用原生查看器。
- 相似照片：滚动查看多组、按钮切换布局、排序、勾选和收藏保持一致。
- 未增加网络客户端沙盒权限，只配置 app-sandbox 与 photos-library；调试构建另含 Xcode 自动生成的 get-task-allow。

## 构建

本机试用构建：

```sh
xcodebuild -project CleanPhoto.xcodeproj -scheme CleanPhoto \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /private/tmp/CleanPhoto-mac-build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

产物位于 `/private/tmp/CleanPhoto-mac-build/Build/Products/Debug-maccatalyst/CleanPhoto.app`。项目保留 Automatic 签名配置，以上覆盖仅用于本机试用；不改变 iPhone 的签名。

## 验证

- Mac Catalyst 构建通过。
- 本机安装副本的深度代码签名校验通过，已实际打开照片授权引导界面并检查窗口布局。
- iPhone 构建继续通过。
- 89 项逻辑回归测试通过。
- 照片授权后的真机图库界面与桌面快捷键仍需用户试用验证；未触碰真实照片作写入测试。

## 原比例缩略图更新

相似相册三列与一列都使用原图比例计算高度并完整适配图片，不再以正方形裁切。混合比例行顶部对齐，行高由最高照片确定。新增横图、竖图与缺失尺寸回归检查，91 项测试通过；Mac 与 iPhone 构建通过。

本次更新时界面自动化在应用退出菜单超时，采用完整新副本原子替换安装包，运行中的旧副本保留在个人应用程序目录的隐藏备份中。需退出并重开以加载新版本；原比例视觉效果待重开确认。
