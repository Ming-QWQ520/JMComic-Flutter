import 'jm_client.dart';
import 'jm_domain.dart';
import 'models.dart';

/// JMComic API 门面（完整对齐 tonquer/JMComic-qt 的全部请求类）。
///
/// 覆盖 req.py 全部业务请求：登录注册、漫画、章节、阅读、搜索、分类、
/// 收藏夹管理、评论、观看历史、J币购买、每周、连载、深夜食堂、签到、随机推荐。
class JmApi {
  JmApi._();
  static final JmApi instance = JmApi._();

  final JmClient _c = JmClient.instance;

  // ===================================================================
  // 账号体系（对齐 LoginReq2 / RegisterReq / RegisterVerifyMailReq /
  // ResetPasswordReq / GetCaptchaReq）
  // ===================================================================

  /// 登录。POST /login （对齐 LoginReq2）。
  ///
  /// 成功后从响应 Cookie 捕获 AVS，自动写入登录态。
  /// 登录接口不携带旧登录态（对齐 qt LoginReq2 pop authorization，
  /// 过期 token 附在登录请求上会被服务端拒绝）。
  Future<LoginData> login(String username, String password) async {
    final r = await _c.postForm(
      'login',
      <String, dynamic>{'username': username, 'password': password},
      false,
      false,
    );
    final data = LoginData.fromMapSafe(r.data);
    if (data == null) throw JmApiException(0, '登录响应解析失败');
    final avs = r.cookies['AVS'] ?? '';
    // 合并登录响应中的所有 cookies 到 sessionCookies，保证后续请求
    // 携带最新的会话标识（对齐 jmcomic python self['cookies'] = cookies）。
    _c.mergeCookies(r.cookies);
    if (data.jwtToken.isNotEmpty || avs.isNotEmpty) {
      _c.setAuth(data.jwtToken, avs.isNotEmpty ? avs : data.s);
    }
    return data;
  }

  /// 获取注册验证码图片（对齐 qt GetCaptchaReq：GET /captcha，
  /// Referer 指向 signup 页）。返回验证码 PNG/JPG 字节。
  ///
  /// 关键修复（注册无法使用）：旧注册流程缺少验证码环节，直接提交
  /// signup 表单会因 verification 字段错误被服务端拒绝。现按 qt 流程：
  /// 先展示验证码图片 → 用户输入 → 提交时作为 verification 上传。
  Future<List<int>> getCaptcha() async {
    final r = await _c.webGetBytes(
      '/captcha',
      headers: <String, String>{'referer': '${JmDomain.webUrl.value}/signup'},
    );
    if (r.status != 200 || r.bytes.isEmpty) {
      throw JmHttpException(r.status, '验证码获取失败(HTTP ${r.status})');
    }
    if (!JmClient.looksLikeImage(r.bytes)) {
      // Cloudflare 挑战页等非图片响应
      throw JmHttpException(0, '验证码响应异常（可能被防护拦截）');
    }
    return r.bytes;
  }

  /// 注册（APP API 域名，对齐官方 JMComic3 2.1.12 FETCH_SIGN_UP_THUNK）。
  ///
  /// 官方 2.1.12 前端源码（Capacitor assets/public/static/js main.js.map
  /// apiPaths.ts）明确：注册走移动 API 域名 `POST /register`，
  /// 参数仅 {username, email, password, password_confirm, gender}，
  /// 与 login 同一套 Token/Tokenparam 签名协议，**无需 Web 验证码**。
  ///
  /// 关键修复（注册无法使用）：旧实现走 Web 域名 /signup（带 captcha），
  /// 该域名受 Cloudflare 严格防护，dart:io TLS 指纹会被拦截
  /// （"Just a moment..." 挑战页），注册必然失败。
  /// 改走 API 域名后与登录共用多级线路容错，成功率与 login 一致。
  ///
  /// API 注册失败时自动回退 Web /signup 流程（[registerViaWeb]）。
  /// 返回 (是否成功, 消息)。
  Future<(bool, String)> register(
    String userId,
    String email,
    String passwd,
    String passwd2, {
    String sex = 'Male',
    String ver = '',
  }) async {
    try {
      final r = await _c.postForm('register', <String, dynamic>{
        'username': userId,
        'email': email,
        'password': passwd,
        'password_confirm': passwd2,
        'gender': sex,
      });
      // 标准加密信封：code=200 即成功；业务错误（如用户名已存在）
      // 由 _decryptResponse 抛 JmApiException，在 catch 中转 Web 流程前
      // 先把服务端消息透出（这类错误换渠道也无法解决）。
      final msg = r.msg.isNotEmpty ? r.msg : '注册成功，请查收验证邮件';
      return (true, msg);
    } on JmApiException {
      rethrow; // 业务错误直接透出真实原因（如「用户名已存在」）
    } catch (_) {
      // 网络/线路层失败 → 回退 Web 注册（Cloudflare 拦截时仍可能失败，
      // 但多一层尝试总是更稳）
      return registerViaWeb(userId, email, passwd, passwd2, sex: sex);
    }
  }

  /// 注册确认（APP API 域名，对齐官方 2.1.12 FETCH_SIGN_UP_CONFIRM_THUNK）。
  ///
  /// 注册成功后官方会发送验证邮件，用户把邮件中的验证码（numcode）
  /// 提交到此接口完成账号验证。
  /// [numcode] 与 [password] 二选一：
  /// - 带 [numcode]：提交邮箱验证码完成验证；
  /// - 带 [password]：重发验证邮件（官方 resend 分支）。
  Future<(bool, String)> registerConfirm(
    String user, {
    String numcode = '',
    String password = '',
  }) async {
    final r = await _c.postForm('confirm', <String, dynamic>{
      'username': user,
      if (numcode.isNotEmpty) 'numcode': numcode,
      if (password.isNotEmpty) 'password': password,
    });
    return (true, r.msg.isNotEmpty ? r.msg : '操作成功');
  }

  /// 重新发送注册验证邮件（对齐官方 resend：POST /confirm {username,
  /// password}）。
  Future<(bool, String)> registerVerifyMail(String user, String password) =>
      registerConfirm(user, password: password);

  /// 重置密码（对齐官方 2.1.12 FETCH_FORGOT_THUNK：API 域名 POST /forgot
  /// {email}）。
  ///
  /// 服务端会把官方生成的随机新密码发送到邮箱。
  /// API 线路失败时回退 Web /lost（qt ResetPasswordReq 同款）。
  Future<(bool, String)> resetPassword(String email) async {
    try {
      final r = await _c.postForm('forgot', <String, dynamic>{'email': email});
      return (true, r.msg.isNotEmpty ? r.msg : '新密码已发送至邮箱');
    } on JmApiException {
      rethrow;
    } catch (_) {
      return resetPasswordViaWeb(email);
    }
  }

  /// Web 端注册回退（对齐 qt RegisterReq：POST /signup + captcha）。
  ///
  /// [ver] 为验证码图片中的字符（GET /captcha 获取）。
  /// 仅在 API 域名注册网络层失败时作为兜底使用。
  Future<(bool, String)> registerViaWeb(
    String userId,
    String email,
    String passwd,
    String passwd2, {
    String sex = 'Male',
    String ver = '',
  }) async {
    final r = await _c.webPost('/signup', <String, dynamic>{
      'username': userId,
      'password': passwd,
      'email': email,
      'verification': ver,
      'password_confirm': passwd2,
      'gender': sex,
      'age': 'on',
      'terms': 'on',
      'submit_signup': '',
    }, referer: '${JmDomain.webUrl.value}/signup');
    return _parseWebMsg(r.body, r.status);
  }

  /// Web 端重置密码回退（对齐 qt ResetPasswordReq：POST /lost）。
  Future<(bool, String)> resetPasswordViaWeb(String email) async {
    final r = await _c.webPost('/lost', <String, dynamic>{
      'email': email,
      'submit_lost': '恢復密碼',
    }, referer: '${JmDomain.webUrl.value}/lost');
    return _parseWebMsg(r.body, r.status);
  }

  /// 解析 Web 响应中的 toastr 消息（对齐 qt ParseMsg）。
  ///
  /// 关键修复（注册无法使用）：
  /// - 3xx：注册域名不可用会重定向（webPost 已关闭自动跟随），
  ///   对齐 qt 诊断「出现301跳转, 无法注册」；
  /// - Cloudflare 挑战页（"Just a moment..."）直接透出原因；
  /// - 200 但无 toastr 时给出更具体的提示而非笼统「操作失败」。
  (bool, String) _parseWebMsg(String body, int status) {
    if (status >= 300 && status < 400) {
      return (false, '注册域名出现 $status 跳转，当前线路不可注册，请稍后重试或切换线路');
    }
    final errRe = RegExp(r"""toastr\['error'\]\("(.*?)"\)""");
    final sucRe = RegExp(r"""toastr\['success'\]\("(.*?)"\)""");
    final suc = sucRe.firstMatch(body);
    if (suc != null) {
      return (true, suc.group(1) ?? '');
    }
    final err = errRe.firstMatch(body);
    if (err != null) {
      return (false, err.group(1) ?? '操作失败');
    }
    if (body.contains('Just a moment')) {
      return (false, '被 Cloudflare 防护拦截，请稍后重试或更换线路');
    }
    if (status >= 400) return (false, 'HTTP $status');
    return (false, '操作失败（服务端未返回结果）');
  }

  // ===================================================================
  // 漫画域（对齐 GetBookInfoReq2 / GetBookEpsInfoReq2 / ReadBookInfoReq2 /
  // GetBookEpsScrambleReq2）
  // ===================================================================

  /// 漫画详情。GET album?id=&comicName= （对齐 GetBookInfoReq2）。
  Future<Album> getAlbum(String id) async {
    final r = await _c.get('album', <String, dynamic>{
      'comicName': '',
      'id': id,
    });
    return Album.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 章节信息。GET chapter?comicName=&skip=&id= （对齐 GetBookEpsInfoReq2）。
  Future<dynamic> getChapter(String epsId) async {
    final r = await _c.get('chapter', <String, dynamic>{
      'comicName': '',
      'skip': '',
      'id': epsId,
    }, false);
    return r.data;
  }

  /// 章节阅读数据（核心）。GET comic_read?lang=&id= （对齐 ReadBookInfoReq2）。
  Future<ReadData> getComicRead(String epsId) async {
    final r = await _c.get('comic_read', <String, dynamic>{'id': epsId});
    return ReadData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 获取章节 scramble_id（对齐 GetBookEpsScrambleReq2，特殊签名头）。
  ///
  /// 响应为 HTML，从中提取 `var scramble_id = NNNN`；
  /// 解析失败返回默认 220980（对齐 qt ParseBookEpsScramble 兜底值）。
  Future<int> getScrambleId(String epsId) async {
    try {
      final r = await _c.getScramble(epsId);
      final body = r.data?.toString() ?? '';
      final mo = RegExp(r'var\s+scramble_id\s*=\s*(\d+)').firstMatch(body);
      if (mo != null) return int.parse(mo.group(1)!);
    } catch (_) {}
    return 220980;
  }

  // ===================================================================
  // 搜索/分类/首页（对齐 GetSearchReq2 / GetCategoryReq2 /
  // GetSearchCategoryReq2 / GetIndexInfoReq2 / GetLatestInfoReq2）
  // ===================================================================

  /// 搜索。GET search （对齐 GetSearchReq2）。
  ///
  /// [searchType] = [site, work, author, tag, character]；
  /// [y]/[m] 年份/月份过滤。
  Future<SearchData> searchComic(
    String keyword,
    int page, {
    String order = 'mr',
    String? searchType,
    String? y,
    String? m,
  }) async {
    final r = await _c.get('search', <String, dynamic>{
      'search_query': keyword,
      'page': page,
      'o': order,
      if (searchType != null && searchType.isNotEmpty)
        'search_type': searchType,
      if (y != null && y.isNotEmpty) 'y': y,
      if (m != null && m.isNotEmpty) 'm': m,
    });
    return SearchData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 分类列表。GET categories （对齐 GetCategoryReq2）。
  Future<CategoriesData> getCategories() async {
    final r = await _c.get('categories');
    return CategoriesData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 分类筛选列表。GET categories/filter （对齐 GetSearchCategoryReq2）。
  ///
  /// [category] = 0/doujin/single/short/another/hanman/meiman/doujin_cosplay/3D；
  /// [order] = mr/mv/mv_m/mv_w/mv_t/mp/tf。
  Future<SearchData> searchCategory(
    String category,
    int page, {
    String order = 'mr',
  }) async {
    final r = await _c.get('categories/filter', <String, dynamic>{
      'page': page,
      'o': order,
      'c': category,
    });
    return SearchData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 首页推荐分区。GET promote （对齐 GetIndexInfoReq2）。
  Future<List<IndexBlock>> getPromote({int page = 0}) async {
    final r = await _c.get('promote', <String, dynamic>{'page': page});
    return IndexBlock.listFrom(r.data);
  }

  /// 最近更新。GET latest （对齐 GetLatestInfoReq2）。
  Future<List<SearchAlbum>> getLatest(int page) async {
    final r = await _c.get('latest', <String, dynamic>{'page': page});
    return SearchAlbum.listFrom(r.data);
  }

  /// 随机推荐。GET random_recommend （对齐 RandomRecommendReq2）。
  Future<List<SearchAlbum>> getRandomRecommend() async {
    final r = await _c.get('random_recommend', <String, dynamic>{});
    return SearchAlbum.listFrom(r.data);
  }

  // ===================================================================
  // 收藏（对齐 GetFavoritesReq2 / AddAndDelFavoritesReq2 /
  // AddFavoritesFoldReq2 / DelFavoritesFoldReq2 / MoveFavoritesFoldReq2）
  // ===================================================================

  /// 收藏列表。GET favorite （对齐 GetFavoritesReq2）。
  ///
  /// [order] = mr(收藏时间)/mp(更新时间)；[fid] 收藏夹 ID（0 默认）。
  Future<FavoriteData> getFavoriteList({
    int page = 1,
    String order = 'mr',
    String fid = '0',
  }) async {
    final r = await _c.get('favorite', <String, dynamic>{
      'page': page,
      'folder_id': fid.isEmpty ? '0' : fid,
      'o': order,
    });
    return FavoriteData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 添加/取消收藏（切换）。POST favorite （对齐 AddAndDelFavoritesReq2）。
  Future<dynamic> addFavorite(String aid) => _c
      .postForm('favorite', <String, dynamic>{'aid': aid})
      .then((r) => r.data);

  /// 新建收藏夹。POST favorite_folder type=add （对齐 AddFavoritesFoldReq2）。
  Future<dynamic> addFavoriteFolder(String name) => _c
      .postForm('favorite_folder', <String, dynamic>{
        'folder_name': name,
        'type': 'add',
      })
      .then((r) => r.data);

  /// 删除收藏夹。POST favorite_folder type=del （对齐 DelFavoritesFoldReq2）。
  Future<dynamic> delFavoriteFolder(String fid) => _c
      .postForm('favorite_folder', <String, dynamic>{
        'folder_id': fid,
        'type': 'del',
      })
      .then((r) => r.data);

  /// 移动收藏到文件夹。POST favorite_folder type=move （对齐 MoveFavoritesFoldReq2）。
  Future<dynamic> moveFavoriteFolder(String bookId, String fid) => _c
      .postForm('favorite_folder', <String, dynamic>{
        'folder_id': fid,
        'type': 'move',
        'aid': bookId,
      })
      .then((r) => r.data);

  // ===================================================================
  // 评论（对齐 GetCommentReq2 / GetMyCommentReq2 / SendCommentReq2）
  // ===================================================================

  /// 漫画评论列表。GET forum?mode=&aid=&page= （对齐 GetCommentReq2）。
  Future<CommentData> getComments(String bookId, {int page = 1}) async {
    final r = await _c.get('forum', <String, dynamic>{
      'mode': 'manhua',
      'aid': bookId,
      'page': page,
    });
    return CommentData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 我的评论。GET forum?mode=undefined&uid=&page= （对齐 GetMyCommentReq2）。
  Future<CommentData> getMyComments(String uid, {int page = 1}) async {
    final r = await _c.get('forum', <String, dynamic>{
      'mode': 'undefined',
      'uid': uid,
      'page': page,
    });
    return CommentData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 发送评论。POST comment （对齐 SendCommentReq2）。
  ///
  /// [cid] 非空时为回复该评论。
  Future<dynamic> sendComment(
    String bookId,
    String comment, {
    String cid = '',
  }) => _c
      .postForm('comment', <String, dynamic>{
        'comment': comment,
        'aid': bookId,
        if (cid.isNotEmpty) 'comment_id': cid,
      })
      .then((r) => r.data);

  // ===================================================================
  // 历史/购买/每周/连载/博客/签到
  // ===================================================================

  /// 当前用户信息（对齐 qt GetUserprofileReq2 → user_profile）。
  ///
  /// 用于购买/收藏/签到等操作后同步余额（J币）、等级等展示字段。
  /// 服务端响应形态不稳定（data 直接是用户对象或包一层），统一走
  /// LoginData.fromMapSafe 的宽松解析；失败返回 null 由调用方兜底。
  ///
  /// 备注：当前公开 API 体系（参考 JUKOMU/JMComic-Api-Java、
  /// ccbkkb/jmcomic-api）均不暴露"上传头像"接口，JM 官方 App 改头像
  /// 走 useredit/{uid} 的图片上传步骤，但该接口未公开文档化、
  /// 也无 multipart 上传实现，故当前 App 暂不支持修改头像。
  /// 仍可通过个人资料页编辑文本字段（昵称、个人简介等）。
  Future<LoginData?> getUserProfile() async {
    final r = await _c.get('user_profile', <String, dynamic>{});
    final data = r.data;
    if (data is Map<String, dynamic>) {
      return LoginData.fromMapSafe(data);
    }
    if (data is Map) {
      return LoginData.fromMapSafe(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// 观看历史。GET watch_list?page= （对齐 GetHistoryReq2）。
  ///
  /// 响应 data 形态（对齐 qt ParseHistoryReq2）：
  /// `{"list": [album...], "total": N}`，部分线路直接返回裸数组，
  /// 这里统一走 [SearchAlbum.listFrom] 的宽松解析兜底全部形态。
  Future<List<SearchAlbum>> getWatchList(int page) async {
    final r = await _c.get('watch_list', <String, dynamic>{
      'page': page,
    }, false);
    return SearchAlbum.listFrom(r.data);
  }

  /// J币购买漫画。POST coin_buy_comics （对齐 GetBuyComicsReq2）。
  Future<dynamic> buyComicWithCoin(String bookId) => _c
      .postForm('coin_buy_comics', <String, dynamic>{'id': bookId})
      .then((r) => r.data);

  /// 每周推荐分类。GET week （对齐 GetWeekCategoriesReq2）。
  Future<dynamic> getWeek({int page = 0}) =>
      _c.get('week', <String, dynamic>{'page': page}).then((r) => r.data);

  /// 每周推荐筛选。GET week/filter （对齐 GetWeekFilterReq2）。
  Future<List<SearchAlbum>> getWeekFilter(
    String id,
    String type, {
    int page = 0,
  }) async {
    final r = await _c.get('week/filter', <String, dynamic>{
      'page': page,
      'id': id,
      'type': type,
    });
    return SearchAlbum.listFrom(r.data);
  }

  /// 每周连载。GET serialization （对齐 GetSerializationReq2）。
  Future<dynamic> getSerialization({
    int date = 1,
    String type = 'all',
    int page = 1,
  }) => _c
      .get('serialization', <String, dynamic>{
        'type': type,
        'date': date,
        'page': page,
      })
      .then((r) => r.data);

  /// 深夜食堂列表。GET blogs （对齐 GetBlogsReq2）。
  Future<dynamic> getBlogs({
    String blogType = 'dinner',
    String searchQuery = '',
    int page = 1,
  }) => _c
      .get('blogs', <String, dynamic>{
        'blog_type': blogType,
        'page': page,
        'search_query': searchQuery,
      }, false)
      .then((r) => r.data);

  /// 深夜食堂详情。GET blog （对齐 GetBlogInfoReq2）。
  Future<dynamic> getBlogInfo(String id) =>
      _c.get('blog', <String, dynamic>{'id': id}, false).then((r) => r.data);

  /// 博客评论。GET forum?bid=&page=&mode=blog （对齐 GetBlogForumReq2）。
  Future<dynamic> getBlogForum(String bid, {int page = 1}) => _c
      .get('forum', <String, dynamic>{
        'bid': bid,
        'page': page,
        'mode': 'blog',
      }, false)
      .then((r) => r.data);

  /// 签到信息。GET daily?user_id= （对齐 GetDailyReq2）。
  Future<dynamic> getDaily(String userId) => _c
      .get('daily', <String, dynamic>{'user_id': userId}, false)
      .then((r) => r.data);

  /// 每日签到。POST daily_chk （对齐 SignDailyReq2 / 官方 FETCH_DAILY_CHECK_THUNK，
  /// 支持可选 date 字段）。
  Future<dynamic> signDaily(String userId, String dailyId, {String? date}) => _c
      .postForm('daily_chk', <String, dynamic>{
        'user_id': userId,
        'daily_id': dailyId,
        if (date != null && date.isNotEmpty) 'date': date,
      })
      .then((r) => r.data);

  // ===================================================================
  // 官方 2.1.12 新增 API（还原自官方前端 apiPaths.ts / actions）
  // ===================================================================

  /// 登出（官方 API_MEMBER_LOOUT：POST /logout）。
  ///
  /// 服务端注销会话；本地登录态由调用方（AppState）清理。
  Future<void> logout() async {
    try {
      // 携带当前 JWT（默认 auth=true），服务端按登录态注销会话
      await _c.postForm('logout', <String, dynamic>{});
    } catch (_) {
      // 登出接口失败不阻塞本地退出（token 只存客户端，服务端会话
      // 自然过期即可）。
    }
  }

  /// 热门标签（官方 API_COMIC_HOT_TAGS：GET /hot_tags）。
  ///
  /// 返回搜索页「热门标签」快捷入口数据，形态由服务端决定
  /// （通常为 {list: [{id, name, ...}]} 或数组）。
  Future<dynamic> getHotTags() =>
      _c.get('hot_tags', <String, dynamic>{}, false).then((r) => r.data);

  // ---------------- 小说（小說模組） ----------------

  /// 小说列表。GET novels （官方 API_NOVEL_LIST，参数 o 排序 / t 分区 /
  /// nid 上限 id / page 页码）。
  Future<dynamic> getNovels({
    String o = '',
    String t = '',
    String nid = '',
    int page = 1,
  }) => _c
      .get('novels', <String, dynamic>{
        'page': page,
        if (o.isNotEmpty) 'o': o,
        if (t.isNotEmpty) 't': t,
        if (nid.isNotEmpty) 'nid': nid,
      }, false)
      .then((r) => r.data);

  /// 小说详情。GET novel?id= （官方 API_NOVEL_DETAIL）。
  Future<dynamic> getNovel(String id) =>
      _c.get('novel', <String, dynamic>{'id': id}, false).then((r) => r.data);

  /// 小说章节列表。GET novelchapters?ncid= （官方 API_NOVEL_CHAPTERS）。
  Future<dynamic> getNovelChapters(String ncid) => _c
      .get('novelchapters', <String, dynamic>{'ncid': ncid}, false)
      .then((r) => r.data);

  /// 小说搜索。GET search_novels?search_query= （官方 API_NOVEL_SEARCH）。
  Future<dynamic> searchNovels(String query, {int page = 1}) => _c
      .get('search_novels', <String, dynamic>{
        'search_query': query,
        'page': page,
      }, false)
      .then((r) => r.data);

  /// 小说留言。POST comment （官方 API_NOVEL_COMMENT，nid 为小说 id）。
  Future<dynamic> sendNovelComment(
    String nid,
    String comment, {
    String cid = '',
  }) => _c
      .postForm('comment', <String, dynamic>{
        'comment': comment,
        'nid': nid,
        if (cid.isNotEmpty) 'comment_id': cid,
      })
      .then((r) => r.data);

  /// 小说收藏列表。GET novel_favorites?page=&folder_id= （官方
  /// API_NOVEL_FAVORITES）。
  Future<dynamic> getNovelFavorites({int page = 1, String folderId = '0'}) => _c
      .get('novel_favorites', <String, dynamic>{
        'page': page,
        'folder_id': folderId.isEmpty ? '0' : folderId,
      }, false)
      .then((r) => r.data);

  /// 编辑小说收藏夹（官方 API_EDIT_NOVEL_FAVORITES：
  /// POST novel_favorites_folder，type=add/del/move）。
  Future<dynamic> editNovelFavoritesFolder({
    required String type,
    String folderId = '',
    String folderName = '',
    String nid = '',
  }) => _c
      .postForm('novel_favorites_folder', <String, dynamic>{
        'type': type,
        if (folderId.isNotEmpty) 'folder_id': folderId,
        if (folderName.isNotEmpty) 'folder_name': folderName,
        if (nid.isNotEmpty) 'nid': nid,
      })
      .then((r) => r.data);

  /// J币购买小说章节（官方 API_NOVEL_COIN_BUY：POST coin_buy_nc）。
  Future<dynamic> buyNovelWithCoin(String ncid) => _c
      .postForm('coin_buy_nc', <String, dynamic>{'ncid': ncid})
      .then((r) => r.data);

  // ---------------- 影片（videos / hanime） ----------------

  /// 影片列表。GET videos （官方 API_VIDEOS_LIST，video_type /
  /// sub_category 可选）。
  Future<dynamic> getVideos({
    int page = 1,
    String searchQuery = '',
    String videoType = '',
    String subCategory = '',
  }) => _c
      .get('videos', <String, dynamic>{
        'page': page,
        if (searchQuery.isNotEmpty) 'search_query': searchQuery,
        if (videoType.isNotEmpty) 'video_type': videoType,
        if (subCategory.isNotEmpty) 'sub_category': subCategory,
      }, false)
      .then((r) => r.data);

  /// 最新 ACG 影片。GET latest_hanime （官方 API_LATEST_HANIME）。
  Future<dynamic> getLatestHanime({int page = 1}) => _c
      .get('latest_hanime', <String, dynamic>{'page': page}, false)
      .then((r) => r.data);

  /// 影片详情。GET video?id= （官方 API_VIDEO_INFO）。
  Future<dynamic> getVideoInfo(String id) =>
      _c.get('video', <String, dynamic>{'id': id}, false).then((r) => r.data);

  /// 建立影片播放 token（官方 API_BAITU_CREATE_TOKEN）。
  Future<dynamic> createBaituToken() => _c
      .postForm('baitu-create-token', <String, dynamic>{})
      .then((r) => r.data);

  // ---------------- 游戏（games） ----------------

  /// 游戏列表。GET allgames （官方 API_GAMES_LIST）。
  Future<dynamic> getGames() =>
      _c.get('allgames', <String, dynamic>{}, false).then((r) => r.data);

  /// 游戏详情。GET game?id= （官方 API_GAME_INFO）。
  Future<dynamic> getGameInfo(String id) =>
      _c.get('game', <String, dynamic>{'id': id}, false).then((r) => r.data);

  // ---------------- 成就 / 任务 ----------------

  /// 任务列表。GET tasks?type=&filter= （官方 API_TASKS_LIST，
  /// type: daily/week/month/newbie...）。
  Future<dynamic> getTasks(String type, {String filter = ''}) => _c
      .get('tasks', <String, dynamic>{
        'type': type,
        if (filter.isNotEmpty) 'filter': filter,
      }, false)
      .then((r) => r.data);

  /// 领取任务奖励 / 排序（官方 FETCH_CHANGE_TASKS：POST tasks
  /// {type, uid, task_id?, new_sort_ids?}）。
  Future<dynamic> changeTasks(
    String type,
    String uid, {
    String taskId = '',
    String newSortIds = '',
  }) => _c
      .postForm('tasks', <String, dynamic>{
        'type': type,
        'uid': uid,
        if (taskId.isNotEmpty) 'task_id': taskId,
        if (newSortIds.isNotEmpty) 'new_sort_ids': newSortIds,
      })
      .then((r) => r.data);

  /// 任务金币购买列表（官方 API_TASKS_BUY_LIST：POST coin
  /// {uid, task_id?}）。
  Future<dynamic> buyTask(String uid, {String taskId = ''}) => _c
      .postForm('coin', <String, dynamic>{
        'uid': uid,
        if (taskId.isNotEmpty) 'task_id': taskId,
      })
      .then((r) => r.data);

  // ---------------- 通知 ----------------

  /// 通知列表。GET notifications?type=&sub_type=&page= （官方
  /// API_NOTIFICATIONS；type: all/album/comment...）。
  Future<dynamic> getNotifications({
    String type = '',
    String subType = '',
    int page = 1,
  }) => _c
      .get('notifications', <String, dynamic>{
        'page': page,
        if (type.isNotEmpty) 'type': type,
        if (subType.isNotEmpty) 'sub_type': subType,
      }, false)
      .then((r) => r.data);

  /// 未读通知数量。GET notifications/unreadCount （官方
  /// API_NOTIFICATIONS_UNREAD）。
  Future<dynamic> getNotificationsUnread() => _c
      .get('notifications/unreadCount', <String, dynamic>{}, false)
      .then((r) => r.data);

  /// 串联（连载）追蹤設定。POST album_sertracking （官方
  /// API_NOTIFICATIONS_SERTRACK）。
  Future<dynamic> serTrackAlbum(String aid, String type) => _c
      .postForm('album_sertracking', <String, dynamic>{
        'aid': aid,
        'type': type,
      })
      .then((r) => r.data);

  /// 追蹤列表。GET album_tracking?page= （官方
  /// API_NOTIFICATIONS_TRACK_LIST）。
  Future<dynamic> getTrackedAlbums({int page = 1}) => _c
      .get('album_tracking', <String, dynamic>{'page': page}, false)
      .then((r) => r.data);

  // ---------------- 標籤收藏 ----------------

  /// 标签收藏列表。GET tags_favorite （官方 API_TAGS_FAVORITE）。
  Future<dynamic> getTagsFavorite() =>
      _c.get('tags_favorite', <String, dynamic>{}, false).then((r) => r.data);

  /// 更新标签收藏（官方 API_TAGS_FAVORITE_UPDATE：POST
  /// tags_favorite_update，data 为 JSON 字符串形态的标签数组）。
  Future<dynamic> updateTagsFavorite(String data) => _c
      .postForm('tags_favorite_update', <String, dynamic>{'data': data})
      .then((r) => r.data);

  // ---------------- 评论增强 ----------------

  /// 评论投票（官方 API_COMMENT_VOTE：POST comment_vote）。
  Future<dynamic> commentVote({
    required String commentId,
    String aid = '',
    String bid = '',
    String nid = '',
    String gid = '',
    String likeType = 'like',
  }) => _c
      .postForm('comment_vote', <String, dynamic>{
        'comment_id': commentId,
        'like_or_dislike': likeType,
        if (aid.isNotEmpty) 'aid': aid,
        if (bid.isNotEmpty) 'bid': bid,
        if (nid.isNotEmpty) 'nid': nid,
        if (gid.isNotEmpty) 'gid': gid,
      })
      .then((r) => r.data);

  /// 删除评论（官方 API_COMMENT_DETELE：POST comment_delete）。
  Future<dynamic> deleteComment(
    String commentId, {
    String aid = '',
    String bid = '',
    String nid = '',
    String gid = '',
  }) => _c
      .postForm('comment_delete', <String, dynamic>{
        'comment_id': commentId,
        if (aid.isNotEmpty) 'aid': aid,
        if (bid.isNotEmpty) 'bid': bid,
        if (nid.isNotEmpty) 'nid': nid,
        if (gid.isNotEmpty) 'gid': gid,
      })
      .then((r) => r.data);

  /// 检查推荐书籍（官方 API_CHECK_RECOMMEND_BN：POST
  /// check_recommend_book {aid}）。
  Future<dynamic> checkRecommendBook(String aid) => _c
      .postForm('check_recommend_book', <String, dynamic>{'aid': aid})
      .then((r) => r.data);

  // ---------------- 簽到獎勵列表 ----------------

  /// 签到奖励配置列表。GET daily_list?user_id= （官方
  /// API_DAILY_LIST：签到奖励选项）。
  Future<dynamic> getDailyList(String userId) => _c
      .get('daily_list', <String, dynamic>{'user_id': userId}, false)
      .then((r) => r.data);

  /// 签到奖励筛选切换。POST daily_list/filter （官方
  /// API_DAILY_LIST_FILTER，data 为 JSON 字符串）。
  Future<dynamic> dailyListFilter(String data) => _c
      .postForm('daily_list/filter', <String, dynamic>{'data': data})
      .then((r) => r.data);

  // ---------------- 用戶編輯 ----------------

  /// 获取用户资料（官方 API_USEREDIT：GET useredit/{uid}）。
  ///
  /// 比旧版 user_profile 返回更完整的可编辑字段（昵称/签名/生日等）。
  Future<dynamic> getUserEdit(String uid) =>
      _c.get('useredit/$uid', <String, dynamic>{}, false).then((r) => r.data);

  /// 编辑用户资料（官方 FETCH_EDIT_INFO_LIST：POST useredit/{uid}，
  /// formData 为可编辑字段表单）。
  Future<dynamic> editUser(String uid, Map<String, dynamic> formData) =>
      _c.postForm('useredit/$uid', formData).then((r) => r.data);

  // ---------------- 其他 ----------------

  /// 点赞（官方 API_LIKE_DATA：POST like {id, like_type?}，
  /// 可用于漫画/小说/评论等）。
  Future<dynamic> addLike(String id, {String likeType = ''}) => _c
      .postForm('like', <String, dynamic>{
        'id': id,
        if (likeType.isNotEmpty) 'like_type': likeType,
      })
      .then((r) => r.data);

  /// J币充能（官方 FETCH_CHARGE：POST coin_buy_charge）。
  Future<dynamic> coinBuyCharge(Map<String, dynamic> params) =>
      _c.postForm('coin_buy_charge', params).then((r) => r.data);

  /// 去广告设置（官方 API_AD_FREE：GET/POST ad_free）。
  Future<dynamic> getAdFree() =>
      _c.get('ad_free', <String, dynamic>{}, false).then((r) => r.data);

  /// 漫画下载打包（官方 API_ALBUM_DOWNLOAD：GET album_download_2?id=）。
  Future<dynamic> getAlbumDownload(String id) => _c
      .get('album_download_2', <String, dynamic>{'id': id}, false)
      .then((r) => r.data);

  // ===================================================================
  // 图片（对齐 DownloadBookReq）
  // ===================================================================

  /// 下载图片。GET {PicUrl}/media/photos/{epsId}/{name}。
  Future<List<int>> downloadImage(String url) => _c.fetchImage(url);

  /// 封面 URL 拼接（{img}/media/albums/{id}_3x4.jpg）。
  String coverUrl(String albumId, {int updateAt = 0}) {
    final host = _c.imgHost;
    if (host.isEmpty) return '';
    final slash = host.endsWith('/') ? '' : '/';
    return '$host${slash}media/albums/${albumId}_3x4.jpg';
  }

  /// 头像 URL 拼接（{img}/media/users/{photo}）。
  String avatarUrl(String photo) {
    final host = _c.imgHost;
    if (host.isEmpty) return '';
    final p = (photo.isEmpty || photo.startsWith('nopic-'))
        ? 'nopic-Male.gif'
        : photo;
    final slash = host.endsWith('/') ? '' : '/';
    return '$host${slash}media/users/$p';
  }

  // ---------- 逃生舱（通用端点） ----------

  /// 通用 GET。
  Future<JmResponse> miscGet(
    String path, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) => _c.get(path, params);

  /// 通用 POST 表单。
  Future<JmResponse> miscPost(
    String path, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) => _c.postForm(path, params);

  /// 通用 POST JSON。
  Future<JmResponse> miscPostJson(String path, Object payload) =>
      _c.postJson(path, payload);
}
