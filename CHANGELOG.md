# v0.1.3 - 发布签名修复、自动检测更新与双通道下载

## 签名修复（覆盖安装）
- 发布 APK 由 debug 签名改为用户 keystore 签名（jmcomic-release.keystore，
  别名 ming）：此前 CI 恒用 debug 签名，与已安装包签名不一致导致无法
  覆盖安装；现 CI 从仓库 Secrets 注入签名材料（JM_KEYSTORE_B64 /
  JM_STORE_PASSWORD / JM_KEY_ALIAS / JM_KEY_PASSWORD），构建前生成
  android/key.properties + keystore，release 构建自动应用
- 本地开发无 key.properties 时自动回退 debug 签名（`flutter run
  --release` 不受影响）；签名材料不入仓库（android/.gitignore 已含
  key.properties / *.keystore）
- CI 新增签名校验步骤：apksigner 比对 APK 证书 SHA-256 指纹与预期
  keystore 指纹，不一致直接构建失败，杜绝发错签名包

## 自动检测更新（每次进入 APP）
- 冷启动进入 APP 后自动检测 GitHub 最新 Release（延迟 1.6s 避让首帧
  与首页请求，失败静默不打扰），发现新版本弹窗提示
- 更新弹窗：新版本号 + 更新内容滚动展示 + 两条下载通道可选：
  「直链下载」（GitHub 直链）与「加速下载」（gh-proxy 前缀，失败自动
  回退直链）；下载中展示进度百分比，完成后自动拉起系统安装器
- 关于页检测更新同步双通道：原单一「立即更新」按钮改为
  「直链下载」+「加速下载」两键，逻辑与弹窗共用 UpdateService
- 下载封装统一入 UpdateService（ABI 最优包挑选逻辑可单测：
  arm64 设备→arm64 包、32 位设备→armeabi-v7a 包、缺失回退 universal）

## 工程
- 版本号 0.1.3（pubspec 0.1.3+5，kAppVersion 同步）
- 新增测试：isNewerVersion 版本比较、pickApkUrl 按 ABI 挑包矩阵

# v0.1.2 - 注册彻底修复、UI 毛玻璃重构、动画设置与主题精简

## bug 修复
- 注册接口彻底修复（两个叠加缺陷，均已线上实测复现）：
  ① **响应信封带日志尾巴**：部分线路 PHP 会在 JSON 信封后附加运行日志
  （实测 `{"code":200,"data":"…"}[2026-10-31] …/php_runtime.log 沒有寫入權限`），
  严格 jsonDecode 抛 "Extra data" FormatException → 被误判「响应非 JSON」→
  全线路轮换失败 → 回退 Web 注册被 Cloudflare 拦截，注册必然失败。
  现改用括号配对扫描的宽松解析（JmClient.parseJsonLenient），信封后带
  任意日志尾巴均可正常解析（附回归测试，含线上实测样本）。
  ② **业务失败被误判为成功**：服务端业务失败（邮箱域名不在白名单 /
  用户名已存在等）同样返回 HTTP 200 + 信封 code=200，真实结果在解密后
  data 字段 `{"status":"fail","msg":…}`。官方 2.1.12 MemberModal 以
  `data.status === "ok"` 判定成功；旧实现把 code=200 一律当成功，用户只
  看到报错文案还误入「邮箱验证」阶段。现 register / confirm / forgot
  统一按 data.status 判定（对齐官方），失败原文透出。
- 注册页邮箱预校验：服务端仅接受 @gmail.com / @qq.com 域名（实测失败
  响应明示），输入框实时校验 + helper 文案提示，避免无效往返
- 搜索历史长按删除时长由 2s 调整为 1s（需求变更），提示文案同步

## UI 重构（毛玻璃 + 动效体系）
- 毛玻璃元素：底部导航栏升级为磨砂玻璃（自定义背景 / 选项透明度 <100%
  时挂 BackdropFilter 高斯模糊，纯色背景自动降级为半透明着色，不白跑
  saveLayer）；登录 / 注册表单卡落在毛玻璃面板上；新增 GlassPanel /
  GlassBottomBar 通用毛玻璃组件（明暗自适应 + 内侧高光描边）
- 动画设置（设置 > 动画设置）：四类动效独立开关，**默认只开启页面转场
  与 Hero**：
  - 页面转场动画（默认开）：滑动 + 淡入转场；关闭后瞬时切换
  - Hero 封面联动（默认开）：列表封面与详情页头图共用 tag + 同一图片
    URL，点击卡片封面飞入头图
  - 物理仿真动画（默认关）：底栏切换页面改用弹簧曲线 animateToPage +
    BouncingScrollPhysics 阻尼回弹；卡片按压缩放带 easeOutBack 过冲
  - 3D 卡片动画（默认关）：封面卡片随触摸/悬停位置透视倾斜（最大 8°，
    松手弹性回正）
- 网格条目错峰入场动画（淡入 + 上移，每屏 12 档循环），滚动加载更有节奏
- 阅读器 / 本地阅读器的明暗切换同步青色方案

## 主题配色
- 去除橙色系：仅保留 浅色·青 / 深色·青 两套（需求变更）；旧用户持久化
  的 light_orange / dark_orange / pink key 自动迁移到对应明暗的青色方案
- 默认主题改为「跟随系统」：设置 > 主题配色新增 模式三选（跟随系统 /
  浅色 / 深色），跟随系统模式下实时响应系统明暗切换；青色双方案以
  预览卡呈现，点击可直接锁定对应明暗

## 工程
- 版本号 0.1.2（pubspec 0.1.2+4，kAppVersion 同步）
- 新增回归测试：宽松 JSON 解析（含线上实测日志尾巴样本）、主题枚举
  迁移映射、动画开关默认值（转场+Hero 开，物理+3D 关）

# v0.1.1 - 注册修复、API 对齐官方 2.1.12 与 APP 内更新修复

## bug 修复
- APP 内更新下载必然失败（PathNotFoundException）：保存路径误把
  Directory 对象直接插值（toString() 为 "Directory: '...'"），生成
  非法路径导致 openWrite 报错；现改用 updateDir.path 拼接，
  downloadUpdate 另加保存目录自动创建防御
- 应用内版本号与发布版本脱节：kAppVersion 硬编码 0.1.0 永远小于
  Release 版本，导致「已是最新版本」判断失效；现同步为 0.1.1，
  并新增测试防漂移（校验 kAppVersion 与 pubspec version 一致）
- 注册接口无法使用（核心修复）：解包官方 JMComic3 2.1.12 前端源码
  （Capacitor assets，含 sourcemap 的 React 业务代码），确认官方注册
  走 **APP API 域名 POST /register**（与登录同 Token/Tokenparam 签名
  协议，参数仅 username/email/password/password_confirm/gender，
  **无需 Web 验证码**）。旧实现走 Web 域名 /signup + captcha，被
  Cloudflare 拦截 Dart TLS 指纹必然失败；现改走 API 域名（复用多级
  线路容错），并保留 Web 流程作为网络层失败时的回退
- 注册后邮箱验证：对齐官方 MemberModal 流程，注册成功进入
  「邮箱验证码」确认阶段（POST /confirm {username, numcode}），
  支持重发验证邮件（POST /confirm {username, password}）
- 忘记密码改走 API 域名 POST /forgot（官方 FETCH_FORGOT_THUNK 同款），
  失败自动回退 Web /lost；协议版本号 headerVer 对齐官方 2.1.12

## 新增 API（还原自官方 2.1.12 apiPaths.ts，全部接入 JmApi 层）
- 账号：登出 /logout（退出登录时自动调用）、用户资料编辑
  useredit/{uid}（GET/POST）、点赞 like、J币充能 coin_buy_charge、
  去广告 ad_free
- 通知：通知列表 notifications、未读数 notifications/unreadCount、
  连载追踪 album_sertracking / album_tracking（个人页新增
  「消息通知」入口页，支持分类筛选与分页）
- 任务：任务列表 tasks?type=、领取奖励 POST tasks、金币购买 coin
  （个人页新增「任务奖励」入口页，每日/每周/每月/新手分类）
- 搜索：热门标签 hot_tags（搜索页顶部新增服务器「热门标签」快捷
  筛选区，失败静默回退内置关键词）
- 小说：novels / novel / novelchapters / search_novels / comment(nid) /
  novel_favorites / novel_favorites_folder / coin_buy_nc
- 影片与游戏：videos / latest_hanime / video / baitu-create-token /
  allgames / game
- 评论增强：comment_vote 投票、comment_delete 删除、
  check_recommend_book 推荐检查
- 其他：tags_favorite / tags_favorite_update 标签收藏、
  daily_list / daily_list/filter 签到奖励、album_download_2 下载打包

## 工程
- CI：Android 构建新增 push 到 main/master 自动触发；Windows 构建
  改为 Android 成功后 workflow_run 链式触发（消除 rolling release
  重建竞争），仍可手动触发

# v0.1.0 - 九项体验修复

> 备注：本次发布 APK 实际构建版本号为 0.1.0（pubspec 0.1.0+1），
> 应用内 kAppVersion 当时亦为 0.1.0。

## bug 修复
- 漫画详情收藏：点击收藏改为从底部弹出「收藏到收藏夹」弹层，
  顶部为「创建收藏夹」入口（新建后即可直接选择），列表含默认收藏
  与全部自建收藏夹；未收藏先收藏再移入所选收藏夹，已收藏时仅移动，
  弹层底部提供「取消收藏」
- 深夜食堂：详情接口响应为 `{"info": {...}}` 嵌套结构，旧代码从顶层
  读 title/content 永远为空（表现为"能看标题点不开正文"）；现按
  info 解包，正文按 文本/配图 拆分渲染（图片走 ImageStore 反爬管线，
  点击可全屏放大），详情请求失败时回退列表项自带正文
- 浏览历史无内容：登录响应 data 内并无 s/AVS 字段，`setUser` 原来用
  空串覆盖了 login() 从 Set-Cookie 捕获的 AVS 会话 Cookie，导致
  watch_list 等需会话 Cookie 的接口 401；现保留 Cookie 侧 AVS，
  refreshUser 合并用户信息时同样不再被空串覆盖
- 搜索/分类/最新列表无限重复渲染：JM 服务端对超出最大页的请求会把
  页码钳制到最后一页并重复返回相同内容（7 个结果被无限向下渲染）；
  AlbumGrid 现按 ID 判重，新页无新条目即判定到底并停止加载
- 发现页滚动：AlbumGrid 在 NestedScrollView 内不再挂接自有
  ScrollController，改绑外层注入的内部 PrimaryScrollController，
  「最新上架」滑到顶部后继续上滑自然展开头部，不再被内部
  下拉刷新拦截；嵌套模式下关闭内层 RefreshIndicator
- 注册接口：补齐缺失的验证码环节（GET /captcha 展示图片 → 输入后随
  signup 表单作为 verification 提交，点击图片可换一张）；webPost 关闭
  自动跟随重定向以暴露「出现301跳转, 无法注册」（对齐 qt 诊断），
  并识别 Cloudflare 拦截页，失败后自动刷新验证码
- 主题配色：仅保留 深色·橙 / 浅色·橙 / 深色·青 / 浅色·青 四套，
  移除粉色系（旧用户持久化 pink key 自动回落浅色·橙，设置页 2×2 呈现）

## 优化
- 排序弹窗：搜索/收藏/分类三处排序（含搜索类型）全部改为自定义
  「液态玻璃」弹出框 —— BackdropFilter 毛玻璃 + 半透明渐变面板 +
  高光描边与柔和投影，明暗主题自适应，点击即生效
- 搜索历史：新增长按 2 秒进入单条删除模式 —— 计时结束轻微震动、
  条目右侧滑入 X，点击 X 即删除该条（点击其它位置退出编辑态）

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
