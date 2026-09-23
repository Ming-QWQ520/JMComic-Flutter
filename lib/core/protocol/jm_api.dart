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
  Future<LoginData> login(String username, String password) async {
    final r = await _c.postForm('login', <String, dynamic>{
      'username': username,
      'password': password,
    });
    final data = LoginData.fromMapSafe(r.data);
    if (data == null) throw JmApiException(0, '登录响应解析失败');
    final avs = r.cookies['AVS'] ?? '';
    if (data.jwtToken.isNotEmpty || avs.isNotEmpty) {
      _c.setAuth(data.jwtToken, avs.isNotEmpty ? avs : data.s);
    }
    return data;
  }

  /// 注册（Web 域名，对齐 RegisterReq）。
  ///
  /// 返回 (是否成功, 消息)。
  Future<(bool, String)> register(
      String userId, String email, String passwd, String passwd2,
      {String sex = 'Male', String ver = ''}) async {
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
    }, referer: '${JmDomain.webUrl.value}signup');
    return _parseWebMsg(r.body, r.status);
  }

  /// 重新发送注册验证邮件（对齐 RegisterVerifyMailReq）。
  Future<(bool, String)> registerVerifyMail(String user, String password) async {
    final r = await _c.webPost('/confirm', <String, dynamic>{
      'username': user,
      'password': password,
      'submit_confirm': '發送EMAIL',
    }, referer: '${JmDomain.webUrl.value}confirm');
    return _parseWebMsg(r.body, r.status);
  }

  /// 重置密码（对齐 ResetPasswordReq）。
  Future<(bool, String)> resetPassword(String email) async {
    final r = await _c.webPost('/lost', <String, dynamic>{
      'email': email,
      'submit_lost': '恢復密碼',
    }, referer: '${JmDomain.webUrl.value}lost');
    return _parseWebMsg(r.body, r.status);
  }

  /// 解析 Web 响应中的 toastr 消息（对齐 qt ParseMsg）。
  (bool, String) _parseWebMsg(String body, int status) {
    final errRe =
        RegExp(r"""toastr\['error'\]\("(.*?)"\)""");
    final sucRe =
        RegExp(r"""toastr\['success'\]\("(.*?)"\)""");
    final suc = sucRe.firstMatch(body);
    if (suc != null) {
      return (true, suc.group(1) ?? '');
    }
    final err = errRe.firstMatch(body);
    if (err != null) {
      return (false, err.group(1) ?? '操作失败');
    }
    if (status >= 400) return (false, 'HTTP $status');
    return (false, '操作失败');
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
  Future<SearchData> searchComic(String keyword, int page,
      {String order = 'mr',
      String? searchType,
      String? y,
      String? m}) async {
    final r = await _c.get('search', <String, dynamic>{
      'search_query': keyword,
      'page': page,
      'o': order,
      if (searchType != null && searchType.isNotEmpty) 'search_type': searchType,
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
  Future<SearchData> searchCategory(String category, int page,
      {String order = 'mr'}) async {
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
  Future<FavoriteData> getFavoriteList(
      {int page = 1, String order = 'mr', String fid = '0'}) async {
    final r = await _c.get('favorite', <String, dynamic>{
      'page': page,
      'folder_id': fid.isEmpty ? '0' : fid,
      'o': order,
    });
    return FavoriteData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 添加/取消收藏（切换）。POST favorite （对齐 AddAndDelFavoritesReq2）。
  Future<dynamic> addFavorite(String aid) =>
      _c.postForm('favorite', <String, dynamic>{'aid': aid}).then((r) => r.data);

  /// 新建收藏夹。POST favorite_folder type=add （对齐 AddFavoritesFoldReq2）。
  Future<dynamic> addFavoriteFolder(String name) =>
      _c.postForm('favorite_folder',
          <String, dynamic>{'folder_name': name, 'type': 'add'}).then((r) => r.data);

  /// 删除收藏夹。POST favorite_folder type=del （对齐 DelFavoritesFoldReq2）。
  Future<dynamic> delFavoriteFolder(String fid) =>
      _c.postForm('favorite_folder',
          <String, dynamic>{'folder_id': fid, 'type': 'del'}).then((r) => r.data);

  /// 移动收藏到文件夹。POST favorite_folder type=move （对齐 MoveFavoritesFoldReq2）。
  Future<dynamic> moveFavoriteFolder(String bookId, String fid) =>
      _c.postForm('favorite_folder',
          <String, dynamic>{'folder_id': fid, 'type': 'move', 'aid': bookId})
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
  Future<dynamic> sendComment(String bookId, String comment,
          {String cid = ''}) =>
      _c.postForm('comment', <String, dynamic>{
        'comment': comment,
        'aid': bookId,
        if (cid.isNotEmpty) 'comment_id': cid,
      }).then((r) => r.data);

  // ===================================================================
  // 历史/购买/每周/连载/博客/签到
  // ===================================================================

  /// 观看历史。GET watch_list （对齐 GetHistoryReq2）。
  Future<List<SearchAlbum>> getWatchList(int page) async {
    final r = await _c.get('watch_list', <String, dynamic>{'page': page}, false);
    return SearchAlbum.listFrom(r.data);
  }

  /// J币购买漫画。POST coin_buy_comics （对齐 GetBuyComicsReq2）。
  Future<dynamic> buyComicWithCoin(String bookId) =>
      _c.postForm('coin_buy_comics', <String, dynamic>{'id': bookId})
          .then((r) => r.data);

  /// 每周推荐分类。GET week （对齐 GetWeekCategoriesReq2）。
  Future<dynamic> getWeek({int page = 0}) =>
      _c.get('week', <String, dynamic>{'page': page}).then((r) => r.data);

  /// 每周推荐筛选。GET week/filter （对齐 GetWeekFilterReq2）。
  Future<List<SearchAlbum>> getWeekFilter(String id, String type,
      {int page = 0}) async {
    final r = await _c.get('week/filter', <String, dynamic>{
      'page': page,
      'id': id,
      'type': type,
    });
    return SearchAlbum.listFrom(r.data);
  }

  /// 每周连载。GET serialization （对齐 GetSerializationReq2）。
  Future<dynamic> getSerialization(
          {int date = 1, String type = 'all', int page = 1}) =>
      _c.get('serialization', <String, dynamic>{
        'type': type,
        'date': date,
        'page': page,
      }).then((r) => r.data);

  /// 深夜食堂列表。GET blogs （对齐 GetBlogsReq2）。
  Future<dynamic> getBlogs(
          {String blogType = 'dinner', String searchQuery = '', int page = 1}) =>
      _c.get('blogs', <String, dynamic>{
        'blog_type': blogType,
        'page': page,
        'search_query': searchQuery,
      }, false).then((r) => r.data);

  /// 深夜食堂详情。GET blog （对齐 GetBlogInfoReq2）。
  Future<dynamic> getBlogInfo(String id) =>
      _c.get('blog', <String, dynamic>{'id': id}, false).then((r) => r.data);

  /// 博客评论。GET forum?bid=&page=&mode=blog （对齐 GetBlogForumReq2）。
  Future<dynamic> getBlogForum(String bid, {int page = 1}) =>
      _c.get('forum', <String, dynamic>{
        'bid': bid,
        'page': page,
        'mode': 'blog',
      }, false).then((r) => r.data);

  /// 签到信息。GET daily?user_id= （对齐 GetDailyReq2）。
  Future<dynamic> getDaily(String userId) =>
      _c.get('daily', <String, dynamic>{'user_id': userId}, false)
          .then((r) => r.data);

  /// 每日签到。POST daily_chk （对齐 SignDailyReq2）。
  Future<dynamic> signDaily(String userId, String dailyId) =>
      _c.postForm('daily_chk', <String, dynamic>{
        'user_id': userId,
        'daily_id': dailyId,
      }).then((r) => r.data);

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
    final p = (photo.isEmpty || photo.startsWith('nopic-')) ? 'nopic-Male.gif' : photo;
    final slash = host.endsWith('/') ? '' : '/';
    return '$host${slash}media/users/$p';
  }

  // ---------- 逃生舱（通用端点） ----------

  /// 通用 GET。
  Future<JmResponse> miscGet(String path,
          [Map<String, dynamic> params = const <String, dynamic>{}]) =>
      _c.get(path, params);

  /// 通用 POST 表单。
  Future<JmResponse> miscPost(String path,
          [Map<String, dynamic> params = const <String, dynamic>{}]) =>
      _c.postForm(path, params);

  /// 通用 POST JSON。
  Future<JmResponse> miscPostJson(String path, Object payload) =>
      _c.postJson(path, payload);
}
