# macOS 官方 GUI 构建与签名边界

## 固定来源（不补写客户端功能）

- 核心：构建本仓库实际 checkout 的 sbvpn commit，保留私有闪连实现；产物附 `core-commit.txt`。
- 客户端：`SagerNet/sing-box-for-apple` 的 dev commit
  `56681841de346fb2185dc6eceba415f6b41bb2b2`，不是 sbvpn 当前经过修改的 Apple gitlink。
- 所有 Apple 源文件保持官方原样，不运行 IPA AppGroup patch，不改变 bundle IDs、entitlements 或 helper XPC 校验。
- Swift 依赖采用该 commit 的 `Package.resolved`；Runestone 子模块固定为
  `baeb3cbf8332d26b4f7b4c175a01f288ebbf3e7f`；Go 依赖采用 sbvpn `go.mod/go.sum`，gomobile v0.1.12。
- Go 1.26.8 与核对时官方 testing CI 一致。Xcode 使用 runner 自带版本并上传版本日志；官方 CI 使用 `xcode-27` 私有标签，若公开 runner SDK 不够则必须换真实可用的 runner，不能修改源码绕过。

## 版本兼容证据及尚未验证项

核对时官方核心 testing commit 为 `dfb80349bf5779ec0a3f834c9ec2794345bff8f0`。
本地 sbvpn 与此官方 commit 的 `experimental/libbox` 整个 git tree 均为
`e6dda6d3607f3fdea54176845624f8b620d5ba38`；官方 build_libbox 文件 blob 均为
`626d221b896af61193cc761a9cf4caf2572c83a2`。
官方 CI 在 testing 上 checkout Apple dev，故固定上述 dev commit，而非随 CI 再追分支。
这证明绑定 API 和官方构建入口一致，不等于已经证明每个 Swift target 编译成功、签名可用或真实 VPN 可连；这些必须以 macOS CI 和签名后实机测试确认。

官方证据入口：
- https://github.com/SagerNet/sing-box/blob/dfb80349bf5779ec0a3f834c9ec2794345bff8f0/.github/workflows/build.yml
- https://github.com/SagerNet/sing-box-for-apple/blob/56681841de346fb2185dc6eceba415f6b41bb2b2/Makefile
- https://github.com/SagerNet/sing-box-for-apple/blob/56681841de346fb2185dc6eceba415f6b41bb2b2/SFM.System/package_from_universal.sh
- https://github.com/SagerNet/sing-box-for-apple/blob/56681841de346fb2185dc6eceba415f6b41bb2b2/HelperService/RootHelperService.swift

## 正确交付形态

官方 standalone 使用 `SFM.System`，不是 App Store 的 `SFM`。
按官方 `make archive_macos_standalone_universal` 中的 xcodebuild 命令产生 `SFM.app`（直接调用保留原始日志），包含 GUI、Library.framework、
NetworkExtension `.systemextension`、RootHelper、LaunchDaemon。不是裸 sing-box 二进制或仅 ZIP。
脚本沿用官方 PKG component plist、distribution XML、LICENSE 资源和 `/Applications` 安装位置，
生成 Universal `.pkg`；再展开实际 PKG，验证 GUI/extension/helper 与 arm64+x86_64 slice。

**这次是 unsigned staging PKG，不能称为可工作的完整 VPN 发行包。**
官方没有无需签名即可运行完整 standalone 的支持入口：Makefile 的 export 使用 Developer ID，
官方打包脚本含真实 application/installer signing，helper XPC 要求 Apple anchor + matching Team ID。
因此此处仅把官方 archive 的 unsigned 构建参数与官方包布局编排起来，跳过依赖证书的 export/sign/notarize；
不伪装官方 unsigned 发行渠道，不 ad-hoc 签名，不降低 helper 校验，不套用 iOS AppGroup workaround。
安装包结构可安装，不代表 Gatekeeper 放行、系统扩展获批或能建立 VPN。

要交付真正可工作的 standalone，需要真实 Developer ID Application 身份、匹配受限
NetworkExtension/system-extension entitlement 的 provisioning profiles、应用与扩展 matching Team ID、
同 Team 的 helper 信任、Developer ID Installer 身份（签 PKG）及公证/用户批准。
官方源码含 SagerNet Team 配置；其他开发者身份不是可无条件直接替代。没有这些凭据时不宣称 tunnel 可用。

## 旧流程问题

- 使用 App Store `SFM` 并复制 IPA AppGroup patch/个人 bundle overrides，偏离官方 macOS standalone。
- 客户端追 moving dev、现有 gitlink 指向修改客户端，来源不可复现。
- `xcodebuild ... || true`、只检测 archive 目录，能误报失败为成功。
- 假定 `sing-box.app`，官方 standalone 实际是 `SFM.app`。
- DMG 失败被吞掉，只 ZIP 可过；未核对系统扩展、helper、双架构或安装包 payload。
- 历史 run 38436021133 实际卡在 release HTTP 403，且先发布后上传丢失产物。

现在原始日志 always 上传，构建失败正常传播，先保存 artifact 再 best-effort release；
产物和 release 都明确 unsigned、unnotarized、签名/实机未验证。
