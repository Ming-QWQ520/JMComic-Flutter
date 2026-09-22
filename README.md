# JMComic-Flutter

> 基于 [Ming-QWQ520/JMcomic-API](https://github.com/Ming-QWQ520/JMcomic-API) 协议逆向实现，使用 Flutter 3.47.5 开发的 Android 漫画阅读器。**仅供学习研究，请勿用于商业用途。**

## 功能特性

- **全量 API 覆盖**：实现 JMcomic-API 逆向出的全部 70 处端点（漫画域 19 / 会员域 19 / 媒体域 19 / 任务域 21 / 其它域 8 + 3 个通用逃生舱）
- **协议完整实现**：
  - `Token` / `Tokenparam` 双请求头签名（MD5）
  - 响应体 AES-256-ECB + PKCS7 解密（含广告接口固定密钥特例）
  - 服务器主机动态解析（远程加密配置 → 解密 → 线路列表 → 兜底配置）
  - 章节图片乱序还原（dart:ui Canvas 像素级还原）
  - 图片 CDN 下载鉴权（Token 头 + AVS Cookie）
- **阅读器**：
  - 音量键翻页（原生 `MainActivity` 拦截转发，可在设置关闭）
  - 上下 / 左右翻页方向切换（阅读器内 + 设置页）
  - 键盘方向键 / 空格 / PgUp / PgDn 翻页
  - 点击左/右 1/3 翻页，中间呼出工具栏
  - 下一页预加载、页码滑杆、双指缩放、屏幕常亮
- **主题**：深色 / 浅色 / 跟随系统（默认跟随系统）
- **搜索**：
  - 输入纯数字漫画编号 → 「编号直达」卡片一键打开详情页
  - 名称 / 作者 / `作者:名字` 语法搜索 + 排序（最新 / 最多浏览 / 最多喜欢 / 最新发布）
  - 热门标签、搜索历史（本地持久化）
- **业务页面**：发现（最新 + 热门标签）、分类（子分类 + 排序）、每周更新、随机推荐、漫画详情（收藏/点赞/追更/J币购买/下载包信息/章节列表）、收藏 / 历史 / 追更列表、通知中心、任务签到、多媒体中心（小说/游戏/视频/博客）、设置（主题/翻页/图源/语言/线路切换）
- **登录体系**：登录 / 注册 / 找回密码 / 退出，登录态本地持久化

## 目录结构

```text
lib/
├── main.dart                     # 入口
├── app.dart                      # MaterialApp + 主题 + 路由
├── core/
│   ├── constants.dart            # 品牌色 / 圆角 / 间距
│   ├── theme/app_theme.dart      # 浅色 / 深色主题
│   ├── protocol/                 # 协议层
│   │   ├── jm_crypto.dart        # MD5 / AES-ECB / Token 签名 / 主机配置解密
│   │   ├── jm_client.dart        # 传输客户端（签名/重试/解密/线路/登录态）
│   │   ├── jm_api.dart           # 全量 70 端点 API 门面
│   │   └── models.dart           # 数据模型
│   └── utils/scramble.dart       # 图片乱序还原算法
├── services/local_store.dart     # 本地持久化（设置/登录态/搜索历史）
├── state/app_state.dart          # 全局状态（主题/设置/登录态）
├── shell/root_page.dart          # 底部导航壳
├── widgets/                      # 共享组件（封面/卡片/网格/反馈）
└── pages/
    ├── home/                     # 发现页 / 每周更新
    ├── explore/                  # 分类 / 分类筛选列表
    ├── search/                   # 搜索（编号直达 + 名称搜索）
    ├── album/                    # 漫画详情
    ├── reader/                   # 阅读器
    ├── user/                     # 我的 / 登录注册 / 收藏历史 / 通知 / 任务
    ├── media/                    # 多媒体中心
    └── settings/                 # 设置
```

## 构建

```bash
flutter pub get
flutter analyze   # 0 issues
flutter test      # 单元测试（协议 / 乱序算法）
flutter build apk --release
```

或直接使用 GitHub Actions：推送到 `main` 分支自动构建，APK 在 Actions Artifacts 中下载（`JMComic-Flutter-v1.0.0.apk`）。

## 免责声明

本项目仅用于网络安全研究与学习。不包含任何账号凭证，`Login` 等会员接口需要用户自行拥有合法账号。使用本项目产生的一切后果由使用者自行承担。
