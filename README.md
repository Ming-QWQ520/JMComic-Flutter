# JMComic-Flutter

基于 [JMcomic-API](https://github.com/Ming-QWQ520/JMcomic-API) 协议逆向实现的 Android 漫画阅读客户端（Flutter 3.47.5）。

> ⚠️ 仅供学习研究使用，请勿用于任何商业用途；请使用自己拥有合法权限的账号。

## 功能

- 覆盖 JMcomic-API 全部 70 个端点（漫画/会员/媒体/任务/其它五大域），完整实现 Token 签名、AES-256-ECB 响应解密、远程主机动态解析（含内置兜底线路）、线路切换
- 首页最新漫画无限流、分类浏览与筛选排序、关键词搜索（含热门标签）
- 漫画详情（章节列表/标签/系列作品）、收藏、点赞、追更、J币购买、浏览历史上报
- 阅读器：**音量键翻页**（原生拦截，可关闭）、**上下/左右翻页**（方向可切换）、键盘方向键、点击翻页、页面预加载、图片乱序还原（dart:ui 像素级还原）
- 多媒体中心：小说 / 游戏 / 视频 / 博客
- 会员：登录 / 注册 / 找回密码 / 通知中心 / 任务签到 / 追更列表
- 深色/浅色模式切换，**默认跟随系统**，持久化保存

## 构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

GitHub Actions 会在 push 时自动构建并在 Artifacts 输出 `app-release.apk`。

## 包信息

- 包名：`com.ming.jmcomic`
- 应用名：`JMComic-Flutter`
