# v0.1.0 - UI 优化与 bug 修复

## 优化
- 自定义背景：增加透明度滑杆（默认 50%），UI 适配改善
- 离线阅读：上下栏样式与在线阅读器同步；支持上下/左右/从右至左三种阅读方向
- 线路测速：所有线路（含 CDN 与代理）均显示 ms 延迟，使用等宽字体避免位置漂移
- 打开下载文件夹：仅在 Android 未授权时跳转系统设置，避免无谓跳转
- 漫画详情页：封面默认截取上半部分；目录每 10 话合并为 x~x 话卡片，点击展开
- 评论页签：内嵌模式下用 PrimaryScrollController 参与 NestedScrollView 协同，
  评论列表滑到顶部后继续上滑会自然过渡到外层头部展开
- "禁漫车" 改为 "JM 号"（含提示弹窗、复制提示、代码注释）
- 整体 UI 性能 + 平滑动画：入场动画、SlideTransition 转场、
  SegmentedButton 全宽对齐、主题紧凑网格（3 列 × 2 行）
- 首页：去除顶部"首页"字样的渐变色，标题改为"发现"
- 页面之间：左右滑动转场（新页从右侧滑入 + 前页轻微左缩），
  支持左边缘向右滑手势返回上一页
- 主题配色：6 套主题以紧凑 Grid 呈现（替代每套一行 RadioListTile）
- 关于项目页：增加 APP 图标（与启动器同源），去除 GitHub Stars 下方小字
- 设置项：阅读设置翻页方向 SegmentedButton 全宽对齐（修复短/长标签位置偏差）

## bug 修复
- 清理下载缓存时不再恢复成默认背景：仅删除子目录保留 baseDir，
  并在"恢复默认背景"时同步删除旧 custom_background.img 文件
- Windows 端"恢复默认背景后再设置显示第一次背景"：背景图改为
  时间戳命名 + 删除旧文件 + Image.file gaplessPlayback:false +
  ValueKey 路径触发重建
- 翻页方向字样位置偏差：SegmentedButton 改为全宽 + styleFrom
  统一 padding，三种模式下位置一致
- 头像 API：当前公开 API（JUKOMU/JMComic-Api-Java、ccbkkb/jmcomic-api）
  均不暴露"上传头像"接口，已加注释说明限制

## 备注
- 版本号：2.2.0 → 0.1.0
