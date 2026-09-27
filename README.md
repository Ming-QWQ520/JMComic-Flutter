# JMComic-Flutter

<p align="center">
  <img src="assets/icon/icon.png" width="96" alt="JMComic-Flutter">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/警告-red?style=for-the-badge" alt="警告Warning">
</p>
 ** 此项目包含R18、一些血腥暴力和猎奇内容，未满18请勿使用，所产生的一切后果与项目开发者无关 ** 


一个使用 **Flutter 3.47.5 (Dart 3.13.4)** 开发的跨平台（Android / Windows）漫画阅读客户端。**仅供学习研究，请勿用于商业用途；请于下载后 24 小时内删除，请支持正版。**

## 功能特性

- **在线阅读**：漫画详情、多章节/单章目录（单章作品支持点击页码直达对应页）、乱序图片还原（Canvas 切片算法）、双指缩放
- **阅读器**：上下滚动 / 左右翻页 / 从右至左三种方向、音量键翻页（可开关）、页码滑杆、可调预加载页数、屏幕常亮、左下角图片线路快捷切换（常驻/跟随两种模式，支持线路测速）
- **下载离线**：整本/单章下载、并发控制、暂停/继续/删除、下载后自动还原乱序并落盘、本地书架离线阅读
- **账号功能**：登录/注册/找回、收藏夹管理（新建/删除/切换）、评论（列表/子评论/发送）、观看历史、每日签到、J币购买
- **浏览发现**：首页推荐分区、每周更新、分类筛选、高级搜索（标签/作者/作品/角色 + 最新/最多点击/最多图片/收藏最多排序）、随机推荐
- **个性化**：6 套主题配色（浅色橙/粉/青、深色橙/粉/青）、自定义背景图与透明度调节、搜索历史
- **网络**：API/图片双线路选择与并行测速（含 CDN/代理线路延迟展示）、DoH 加密解析、失败自动切换下一域名
- **安全**：应用锁（指纹/面容/锁屏密码，基于系统 BiometricPrompt）
- **更新**：应用内检测更新（GitHub API），发现新版本显示更新内容，一键下载 APK（gh-proxy.com 加速）并拉起安装
- **桌面小组件快捷方式**：长按图标快捷菜单（随机推荐 / 每周更新）

## 下载安装

1. 前往 [Releases · latest](https://github.com/Ming-QWQ520/JMComic-Flutter/releases/tag/latest) 下载对应架构 APK：
   - `arm64-v8a`：现代手机（2016 年后绝大多数机型）✅ 推荐
   - `universal`：不确定架构时选这个
   - `armeabi-v7a`：老旧 32 位手机
   - `x86_64`：模拟器 / Chromebook
2. 或在应用内「设置 → 关于 → 检测更新」直接检测并下载安装（国内网络走 gh-proxy.com 加速）。

Windows 桌面版由 `build-windows.yml` 独立构建（解压后运行 `jmcomic.exe`）。

## 本地构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Android 工具链：AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0 / JDK 21。
发版时请注意同步 `pubspec.yaml` 的 `version:` 与 `lib/core/constants.dart` 的 `kAppVersion`（应用内检测更新据此比对）。

## 项目结构

```text
lib/
├── main.dart                     # 入口
├── app.dart                      # MaterialApp + 主题 + 路由 + 应用锁门卫
├── core/
│   ├── constants.dart            # 版本常量与主题方案
│   ├── theme/app_theme.dart      # 6 套主题工厂
│   ├── protocol/                 # 协议层
│   │   ├── jm_crypto.dart        # MD5 / AES-ECB / Token 签名 / 主机配置解密
│   │   ├── jm_domain.dart        # 域名体系 + 远程配置热更新
│   │   ├── jm_client.dart        # 传输客户端（签名/DoH/域名切换/解密/图片下载）
│   │   ├── jm_api.dart           # 业务端点门面
│   │   └── models.dart           # 数据模型
│   └── utils/scramble.dart       # 图片乱序还原
├── services/
│   ├── local_store.dart          # SharedPreferences 封装
│   ├── download_manager.dart     # 下载管理器（并发/断点/本地书架）
│   ├── storage_service.dart      # 存储权限 / 打开文件夹 / 分享 / 安装更新
│   ├── app_lock_service.dart     # 应用锁（local_auth 本地认证）
│   ├── github_service.dart       # 仓库信息 / 检测更新 / APK 加速下载
│   └── widget_bridge.dart        # 长按图标快捷菜单桥
├── state/app_state.dart          # 全局状态（主题/线路/登录态/应用锁）
├── shell/root_page.dart          # 底部导航壳
├── pages/
│   ├── home/ explore/ search/    # 首页 / 分类 / 搜索
│   ├── album/                    # 漫画详情 / 评论区
│   ├── reader/                   # 在线阅读器（线路切换/缩放/音量键）
│   ├── download/                 # 下载管理 / 本地书架 / 离线阅读器
│   ├── sign/ blogs/              # 签到 / 深夜食堂
│   ├── user/                     # 我的 / 收藏夹 / 历史 / 登录 / 关于
│   └── settings/                 # 设置（主题/线路/阅读/安全/个性化）
└── widgets/                      # 共享组件（封面/卡片/网格/反馈/应用锁门卫）
```

## CI/CD

Android 构建为手动触发（`workflow_dispatch`），编译 universal / arm64-v8a / armeabi-v7a / x86_64 四种 APK 并更新 rolling release（tag `latest`）；推送 `v*` 标签会创建正式 Release。Windows 桌面构建独立在 `build-windows.yml`。

## 致谢

- [tonquer/JMComic-qt](https://github.com/tonquer/JMComic-qt) — API 协议与功能设计参考
- [jmcomic (Python)](https://github.com/hect0x7/JMComic-Core) — JM API 协议的开源实现参考
- [gh-proxy.com](https://gh-proxy.com) — GitHub 资源下载加速
- [Flutter](https://flutter.dev) — 跨平台 UI 框架

## 开源协议

本项目基于 [GNU AGPL-3.0](LICENSE) 开源：任何基于本项目的修改与服务化部署都需以同协议开源。注意：协议仅覆盖本项目代码本身，应用所访问的内容服务归原权利方所有。

## 免责声明

本项目为学习研究用途的客户端实现，不存储任何漫画资源，所有内容均来自公开接口。请于下载后 24 小时内删除，请支持正版。
