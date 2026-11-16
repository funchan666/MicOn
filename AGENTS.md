# MicOn 项目交接

本项目以本地视频文件的导入、播放、编辑和导出为核心，K 歌课程与练习为补充。使用原生 SwiftUI，最低 iOS 17，工程与共享 Scheme 均为 `MicOn`。本文件记录 2026-11-13 的交付和用户确认的约定。后续状态以本项目的代码、配置和新验证记录为准。

## 业务与测试约定

- 在线业务沿用 Clipo。从首页「打开链接」输入课程链接或短码，通过 `search-check` 进入可纵向切换的全屏播放器。游客登录、推荐、收藏、离线播放、编辑导出、额度、开屏与激励广告、订阅和恢复购买继续走原有路径。订阅与媒体导出保留服务端权益校验。
- 当前是测试配置。API 为 `https://devapi.io-jp.com`，`getV2.name` 为 `MicOn`，取自 `MICON_RELEASE_NAME`。Bundle ID 为 `im.seex.lobo`，游客登录 `source` 和业务 `packageName` 同源。五包共用测试 BID，同一设备依次安装。
- 广告使用 Clipo 的 Google 官方演示 App ID 和开屏、激励广告位。官网、用户协议、隐私政策使用 HTTPS 占位链接。测试商品为月付 `coins_1.99` USD 9.99、年付 `conis_4.99` USD 99.99。会员页展示 StoreKit 返回的本地化价格和账期。
- 播放联调用 Clipo 的原测试短码，在首页手动输入。短码和广告配置见工具包的 [Clipo 基线](/Users/chengdupengyuyan/.codex/skills/toolkit/references/clipo-baseline.md) 第 1、5 节。Clipo 源工程位于 `/Users/chengdupengyuyan/Fun/Clipo`。
- 用户确认本项目测试通过后，再收集尚未提供的正式 BID、API 域名、广告 App ID 和广告位、官网、用户协议和隐私政策。切换时 Bundle ID、登录 `source` 与业务 `packageName` 一起使用正式 BID，`getV2.name` 继续用 `MicOn`。核对正式月年商品与后台订单映射。

## 本项目的原创界面

- **视频首页**。首屏可从文件选取视频，也可从相册导入。最近打开和当前视频使用本地视频帧。链接和短码为次级入口，课程集合、试唱日志和 K 歌指南归入「课程与练习」。
- 底栏依次为视频、工具、文件、我。播放和编辑使用深色背景。工具可直接处理当前文件，支持剪辑、裁剪、旋转、镜像、变速及音频提取。成品保存到导出分组，可通过系统分享面板另存。
- **文件页**。按导入、下载和导出分组，收藏保留次级入口。列表优先显示文件名与视频帧，无法提取的下载帧使用课程封面。实现见 `MicOn/Features/LibraryView.swift`。
- **Plus 与「我」**。Plus 展示导出、在线观看和下载权益，价格及账期使用 StoreKit 数据，恢复购买为独立按钮。「我」页按账户、会员、在线额度和设置排列。实现见 `MicOn/Features/MembershipView.swift`。
- 后续 UI 工作按全局 UI 技能约定使用 `ui-design-reference`、`ui-taste` 和适用的原创素材工作流。iOS 适配按 Duo 约定，保留当前 SwiftUI 和各主题的交互设计。

## 交付时的验证状态

- 已静态核对视频打开、编辑与保存、文件分类、课程返回路径、StoreKit 展示及开屏广告回调的接线。
- 待运行验证的事项包括编译、模拟器和真机显示、Duo 布局、测试后台返回、短码播放、广告以及 Apple Sandbox 购买与恢复。按用户约定，默认只做静态核对，编译和测试在用户明确要求时执行。
