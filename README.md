# JMComic-Flutter

基于 [JMcomic-API](https://github.com/Ming-QWQ520/JMcomic-API) 协议逆向成果实现的
**Android 漫画阅读器**，使用 Flutter 3.47.5 构建。仅用于协议学习与研究。

> ⚠️ 免责声明：本项目仅用于网络协议学习研究，不包含任何账号凭证；
> 请勿用于商业用途或大规模抓取，使用本项目产生的一切后果由使用者自行承担。
> `Login` 等会员接口需要用户自行拥有合法账号。

## 功能特性

- **完整协议实现**（Flutter/Dart 复刻 JMcomic-API 逆向的协议栈）
  - 服务器主机动态解析：远程加密配置（3 镜像）→ AES-256-ECB 解密 → 线路列表，失败回退 APK 内置兜底配置
  - 请求签名：`Token` / `Tokenparam` 双请求头（每请求重新生成）
  - 响应解密：`Base64(AES-256-ECB(PKCS7(JSON)))`，双密钥依次尝试，广告接口固定密钥特例
  - 章节图片乱序还原：切片数算法（md5 末字符 + 查表）与像素级还原（dart:ui Canvas 实现）
  - 图片 CDN 下载鉴权（图片请求同样携带签名头）
  - 全部 **70 个业务端点**（漫画 / 会员 / 媒体 / 任务 / 其它五大域）均在 `lib/api/jm_api.dart` 实现
- **功能完整的阅读 App**
  - 首页最新漫画（无限滚动）、随机推荐、每周更新表
  - 分类浏览（分类 → 子分类 → 排序筛选）
  - 搜索（关键词 / 排序 / 热门标签）
  - 漫画详情（章节列表、标签、系列作品、点赞 / 收藏 / 追更 / J币购买 / 下载包信息）
  - 阅读器：**音量键翻页**（原生 MethodChannel 拦截，可开关）、**上下 / 左右翻页**方向切换、
    键盘方向键翻页、点击左右 1/3 区域翻页、页面跳转滑块、下一页预加载、双指缩放
  - 登录 / 注册 / 找回密码，收藏夹、浏览历史、追更列表、通知中心、任务签到
  - 多媒体中心（小说 / 游戏 / 视频 / 博客，覆盖媒体域全部接口）
  - 线路热切换（设置页）
- **深色 / 浅色模式**：跟随系统（默认）/ 浅色 / 深色，设置持久化
- **CI**：GitHub Actions 自动 `flutter analyze` + `flutter test` + 编译 release APK

## 构建

```bash
flutter pub get
flutter analyze   # 静态检查：0 issues
flutter test      # 单元测试：协议核心算法
flutter build apk --release
```

也可直接在 GitHub Actions 手动触发（workflow_dispatch），APK 产物在 Artifacts 下载。

## 项目结构

```text
lib/
├── main.dart                  # 应用入口 + 主题（跟随系统默认）
├── api/
│   ├── jm_crypto.dart         # Token 签名 / AES-256-ECB 解密 / 主机配置解密
│   ├── jm_client.dart         # 传输客户端（重试/解密/线路/登录态）
│   ├── jm_api.dart            # 全部 70 端点（comic/member/media/task/misc）
│   └── models.dart            # 数据模型（类型不稳定字段规范化）
├── state/app_state.dart       # 主题 / 阅读 / 图源 / 登录态（持久化）
├── utils/scramble.dart        # 图片乱序还原算法（dart:ui 实现）
├── widgets/common.dart        # 封面卡片 / 无限滚动网格 / 状态组件
└── pages/                     # 首页 / 分类 / 搜索 / 详情 / 阅读器 / 我的 ...
android/app/src/main/kotlin/com/ming/jmcomic/MainActivity.kt   # 音量键拦截
```

## 包信息

- Application ID: `com.ming.jmcomic`
- 应用名称: `JMComic-Flutter`
- Flutter: `3.47.5 stable`（Dart 3.13.4）
