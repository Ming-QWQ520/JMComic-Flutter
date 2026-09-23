# JMComic-Flutter

> 基于 [tonquer/JMComic-qt](https://github.com/tonquer/JMComic-qt) 所使用的 API 协议重构，使用 Flutter 3.47.5 (Dart 3.13.4) 开发的 Android 漫画阅读器。**仅供学习研究，请勿用于商业用途。**

## 重构说明（v2.0）

本项目已将 API 层完整迁移至 JMComic-qt（Python/PySide6 桌面客户端）所使用的协议体系：

| 维度 | 对齐内容 |
|------|----------|
| 请求签名 | `token = MD5("{ts}18comicAPP")`，`tokenparam = "{ts},2.1.7"`（对齐 qt `GetHeader` / `GlobalConfig.HeaderVer`） |
| scramble 接口 | `/chapter_view_template` 使用 `18comicAPPContent` 密钥签名（对齐 qt `GetHeader2`，用错密钥会 403） |
| 响应解密 | `Base64(AES-256-ECB + PKCS7(JSON))`，密钥 `MD5("{ts}185Hcomic3PAPP7R")`（对齐 qt `ParseData` → jmcomic 库 `decode_resp_data`） |
| API 域名 | `www.cdnhjk.net` / `www.cdngwc.cc` / `www.cdngwc.net` / `www.cdngwc.club` + CDN/代理线路（对齐 qt `Url2List`） |
| 图片域名 | `cdn-msp.jmapiproxy1.cc` / `cdn-msp.jmapiproxy3.cc` / `cdn-msp.jmapinodeudzn.net` / `cdn-msp.jmdanjonproxy.xyz`（对齐 qt `PicUrlList`） |
| 远程配置 | 启动拉取 `newsvr-2025.txt`（k=v 文本）按版本号热更新全部域名（对齐 qt `UpdateSetting`） |
| DoH | `parse.jpacg.cc` / `doh.pub` / `parse2.jpacg.cc` / `dot.pub`，IP 直连 + 信任证书（对齐 qt `QtDomainMgr`） |
| 失败切换 | API 请求失败自动切换下一域名重试（对齐 qt `ResetToSwitchNextUrl`） |
| 注册体系 | 注册/重发验证邮件/找回密码走 Web 域名表单（对齐 qt `RegisterReq` / `RegisterVerifyMailReq` / `ResetPasswordReq`） |
| 图片回退 | `_3x4` 封面失败自动回退无后缀原图（对齐 qt `DownloadBookReq.resetUrl`） |

## 功能特性

- **全端点对齐 JMComic-qt**：登录 / 注册 / 找回、漫画详情、章节、阅读、scramble 获取、搜索（search_type 高级搜索）、分类筛选（mr/mv/mv_m/mv_w/mv_t/mp/tf 七种排序）、收藏夹管理（新建/删除/切换）、评论（列表/子评论/发送/我的评论）、观看历史、J币购买、每周更新（manga/hanman/another）、深夜食堂（blogs）、每日签到（daily/daily_chk）、随机推荐
- **阅读器**：
  - 音量键翻页（原生 MethodChannel 拦截，可在设置关闭）
  - 上下 / 左右 / 日漫（右到左）三种翻页方向
  - 章节图片乱序还原（dart:ui Canvas，切片数算法与 qt `GetSegmentationNum` 一致）
  - 可调预加载页数（1-10）、页码滑杆、双指缩放、屏幕常亮
- **下载管理**（对齐 qt DownloadView / 本地书架）：
  - 整本下载 / 单章下载、并发数控制、暂停/继续/删除
  - 下载后自动乱序还原落盘（对齐 qt `SegmentationPictureToDisk`）
  - 本地书架 + 离线阅读器
- **主题**：6 套配色完整对齐 qt QSS 主题（浅色橙/粉/青、深色橙/粉/青）
- **其他**：搜索历史、线路测速、DoH 开关、下载缓存清理、编号直达

## 目录结构

```text
lib/
├── main.dart                     # 入口
├── app.dart                      # MaterialApp + 主题 + 路由
├── core/
│   ├── constants.dart            # 主题方案（对齐 qt QSS 配色）
│   ├── theme/app_theme.dart      # 6 套主题工厂
│   ├── protocol/                 # 协议层（对齐 JMComic-qt）
│   │   ├── jm_crypto.dart        # MD5 / AES-ECB / Token 签名 / 主机配置解密
│   │   ├── jm_domain.dart        # qt GlobalConfig 域名体系 + 远程配置热更新
│   │   ├── jm_client.dart        # 传输客户端（签名/DoH/域名切换/解密/图片下载）
│   │   ├── jm_api.dart           # qt 全部业务端点门面
│   │   └── models.dart           # 数据模型
│   └── utils/scramble.dart       # 图片乱序还原
├── services/
│   ├── local_store.dart          # SharedPreferences 封装
│   └── download_manager.dart     # 下载管理器（并发/断点/本地书架）
├── state/app_state.dart          # 全局状态（主题/线路/DoH/登录态）
├── shell/root_page.dart          # 底部导航壳
├── pages/
│   ├── home/                     # 首页（promote 分区 + 最新） / 每周更新
│   ├── explore/                  # 分类
│   ├── search/                   # 搜索
│   ├── album/                    # 漫画详情 / 评论区
│   ├── reader/                   # 在线阅读器
│   ├── download/                 # 下载管理 / 本地书架 / 离线阅读器
│   ├── sign/                     # 每日签到
│   ├── blogs/                    # 深夜食堂
│   ├── user/                     # 我的 / 收藏夹 / 历史 / 登录注册
│   └── settings/                 # 设置（主题/线路/DoH/阅读）
└── widgets/                      # 共享组件（封面/卡片/网格/反馈）
```

## 构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Android 工具链：AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0 / JDK 21。

## CI/CD

推送至 `main`/`master` 或手动触发 `workflow_dispatch` 即可编译多架构 APK（universal / arm64-v8a / armeabi-v7a / x86_64）；推送 `v*` 标签会自动创建 GitHub Release 并附上 APK。
