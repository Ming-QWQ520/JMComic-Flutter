import 'jm_client.dart';
import 'models.dart';

/// JMComic 全量 API 门面。
///
/// 覆盖 JMcomic-API 逆向出的全部 70 处端点（60 个路径，GET/POST 复用），
/// 按五大业务域组织：漫画 comic / 会员 member / 媒体 media / 任务 task / 其它 misc。
class JmApi {
  JmApi._();
  static final JmApi instance = JmApi._();

  final JmClient _c = JmClient.instance;

  // ===================================================================
  // 漫画域 ComicService（19 个方法）
  // ===================================================================

  /// 3.1 获取 APP 设置。GET setting
  Future<SettingData> getSetting({int appImgShunt = 1}) async {
    final r = await _c.get('setting', <String, dynamic>{
      'app_img_shunt': appImgShunt,
      't': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return SettingData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 3.2 上报语言设置。POST setting
  Future<SettingData> updateSetting(String language) async {
    final r = await _c.postForm('setting', <String, dynamic>{
      'language': language,
      't': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return SettingData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 3.3 获取分类列表。GET categories
  Future<CategoriesData> getCategories() async {
    final r = await _c.get('categories');
    return CategoriesData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 3.4 分类筛选列表。GET categories/filter
  Future<List<SearchAlbum>> getCategoriesFilter({
    String categorySub = '',
    int page = 1,
    String order = 'mr',
  }) async {
    final r = await _c.get('categories/filter', <String, dynamic>{
      if (categorySub.isNotEmpty) 'category_sub': categorySub,
      'page': page,
      'o': order,
    });
    return SearchAlbum.listFrom(r.data);
  }

  /// 3.5 漫画详情。GET album
  Future<Album> getAlbum(String id) async {
    final r = await _c.get('album', <String, dynamic>{'id': id});
    return Album.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 3.6 章节信息。GET chapter
  Future<dynamic> getChapter(String id) async {
    final r = await _c.get('chapter', <String, dynamic>{'id': id});
    return r.data;
  }

  /// 3.7 章节阅读数据（核心）。GET comic_read
  Future<ReadData> getComicRead(String id, {String express = 'off'}) async {
    final r = await _c
        .get('comic_read', <String, dynamic>{'id': id, 'express': express});
    return ReadData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 3.8 下载包信息（需登录）。GET album_download_2/{id}
  Future<dynamic> getAlbumDownload(String id) async {
    final r = await _c.get('album_download_2/$id');
    return r.data;
  }

  /// 3.9 搜索漫画。GET search
  Future<SearchData> searchComic(String keyword, int page,
      {String order = 'mr', int mainTag = 0}) async {
    final r = await _c.get('search', <String, dynamic>{
      'search_query': keyword,
      'page': page,
      'main_tag': mainTag,
      'o': order,
    });
    return SearchData.fromMap(Map<String, dynamic>.from(r.data ?? {}));
  }

  /// 3.10 最新漫画。GET latest
  Future<List<SearchAlbum>> getLatest(int page) async {
    final r = await _c.get('latest', <String, dynamic>{'page': page});
    return SearchAlbum.listFrom(r.data);
  }

  /// 3.11 热门标签。GET hot_tags
  Future<dynamic> getHotTags() async {
    final r = await _c.get('hot_tags');
    return r.data;
  }

  /// 3.12 随机推荐。GET random_recommend
  Future<dynamic> getRandomRecommend() async {
    final r = await _c.get('random_recommend');
    return r.data;
  }

  /// 3.13 首页推荐。GET promote
  Future<dynamic> getPromote() async {
    final r = await _c.get('promote');
    return r.data;
  }

  /// 3.14 推荐列表。GET promote_list
  Future<dynamic> getPromoteList({int page = 1}) async {
    final r = await _c.get('promote_list', <String, dynamic>{'page': page});
    return r.data;
  }

  /// 3.15 连载列表。GET serialization
  Future<dynamic> getSerialization({int page = 1}) async {
    final r = await _c.get('serialization', <String, dynamic>{'page': page});
    return r.data;
  }

  /// 3.16 每周更新表。GET week
  Future<dynamic> getWeek() async {
    final r = await _c.get('week');
    return r.data;
  }

  /// 3.16 每周更新筛选。GET week/filter
  Future<dynamic> getWeekFilter(Map<String, dynamic> params) async {
    final r = await _c.get('week/filter', params);
    return r.data;
  }

  /// 3.17 下载章节图片（核心）。GET {CDN}/media/photos/...
  Future<List<int>> downloadImage(String url) => _c.fetchImage(url);

  /// 3.18 封面 URL 拼接。
  String coverUrl(String albumId, {int updateAt = 0}) {
    final host = _c.imgHost;
    if (host.isEmpty) return '';
    final slash = host.endsWith('/') ? '' : '/';
    return '$host${slash}media/albums/${albumId}_3x4.jpg?v=$updateAt';
  }

  /// 3.18 头像 URL 拼接。
  String avatarUrl(String photo) {
    final host = _c.imgHost;
    if (host.isEmpty) return '';
    final p = photo.isEmpty ? 'nopic-Male.gif' : photo;
    final slash = host.endsWith('/') ? '' : '/';
    return '$host${slash}media/users/$p';
  }

  // ===================================================================
  // 会员域 MemberService（19 个方法）
  // ===================================================================

  /// 4.1 登录（核心）。POST login
  Future<LoginData> login(String username, String password) async {
    final r = await _c.postForm('login', <String, dynamic>{
      'username': username,
      'password': password,
    });
    final data = LoginData.fromMapSafe(r.data);
    if (data == null) throw JmApiException(0, '登录响应解析失败');
    if (data.jwtToken.isNotEmpty || data.s.isNotEmpty) {
      _c.setAuth(data.jwtToken, data.s);
    }
    return data;
  }

  /// 4.2 退出登录。POST logout
  Future<void> logout() async {
    try {
      await _c.postForm('logout');
    } finally {
      _c.setAuth('', '');
    }
  }

  /// 4.3 注册账号。POST register
  Future<dynamic> register(Map<String, dynamic> form) =>
      _c.postForm('register', form).then((r) => r.data);

  /// 4.4 找回密码。POST forgot
  Future<dynamic> forgot(Map<String, dynamic> form) =>
      _c.postForm('forgot', form).then((r) => r.data);

  /// 4.5 获取用户资料（需登录）。GET useredit/{uid}
  Future<dynamic> getUserInfo(String uid) =>
      _c.get('useredit/$uid').then((r) => r.data);

  /// 4.6 更新用户资料（需登录）。POST useredit/{uid}
  Future<dynamic> updateUserInfo(String uid, Map<String, dynamic> fields) =>
      _c.postForm('useredit/$uid', fields).then((r) => r.data);

  /// 4.7 收藏夹列表（需登录）。GET favorite
  Future<List<SearchAlbum>> getFavoriteList(
      {int page = 1, String order = 'mr', String folderId = ''}) async {
    final r = await _c.get('favorite', <String, dynamic>{
      'page': page,
      'order': order,
      if (folderId.isNotEmpty) 'folder_id': folderId,
    });
    return SearchAlbum.listFrom(r.data);
  }

  /// 4.8 收藏漫画（需登录）。POST favorite
  Future<dynamic> addFavorite(String aid) =>
      _c.postForm('favorite', <String, dynamic>{'aid': aid}).then((r) => r.data);

  /// 4.9 编辑收藏夹（需登录）。POST favorite_folder
  Future<dynamic> editFavoriteFolder(Map<String, dynamic> params) =>
      _c.postForm('favorite_folder', params).then((r) => r.data);

  /// 4.10 收藏的标签（需登录）。GET tags_favorite
  Future<dynamic> getTagsFavorite() =>
      _c.get('tags_favorite').then((r) => r.data);

  /// 4.10 更新收藏的标签（需登录）。POST tags_favorite_update
  Future<dynamic> updateTagsFavorite(Map<String, dynamic> params) =>
      _c.postForm('tags_favorite_update', params).then((r) => r.data);

  /// 4.11 点赞（需登录）。POST like
  Future<dynamic> like(Map<String, dynamic> params) =>
      _c.postForm('like', params).then((r) => r.data);

  /// 4.12 浏览历史（需登录）。GET watch_list
  Future<List<SearchAlbum>> getWatchList(int page) async {
    final r = await _c.get('watch_list', <String, dynamic>{'page': page});
    return SearchAlbum.listFrom(r.data);
  }

  /// 4.12 上报浏览历史（需登录）。POST watch_list
  Future<dynamic> updateWatchList(String id) =>
      _c.postForm('watch_list', <String, dynamic>{'id': id}).then((r) => r.data);

  /// 4.13 论坛列表（需登录）。GET forum
  Future<dynamic> getForumList({int page = 1}) =>
      _c.get('forum', <String, dynamic>{'page': page}).then((r) => r.data);

  /// 4.14 发送评论/帖子（需登录）。POST comment
  Future<dynamic> sendComment(Map<String, dynamic> params) =>
      _c.postForm('comment', params).then((r) => r.data);

  /// 4.15 评论投票（需登录）。POST comment_vote
  Future<dynamic> voteComment(Map<String, dynamic> params) =>
      _c.postForm('comment_vote', params).then((r) => r.data);

  /// 4.15 删除评论（需登录）。POST comment_delete
  Future<dynamic> deleteComment(Map<String, dynamic> params) =>
      _c.postForm('comment_delete', params).then((r) => r.data);

  /// 4.16 检查推荐横幅（需登录）。POST check_recommend_book
  Future<dynamic> checkRecommendBook(String aid) =>
      _c.postForm('check_recommend_book', <String, dynamic>{'aid': aid})
          .then((r) => r.data);

  // ===================================================================
  // 媒体域 MediaService（19 个方法：小说 / 游戏 / 视频 / 博客）
  // ===================================================================

  /// 5.1 小说列表。GET novels
  Future<dynamic> getNovelList({int page = 1, String order = 'mr'}) =>
      _c.get('novels', <String, dynamic>{'page': page, 'order': order})
          .then((r) => r.data);

  /// 5.2 小说详情。GET novel
  Future<dynamic> getNovelDetail(String id) =>
      _c.get('novel', <String, dynamic>{'id': id}).then((r) => r.data);

  /// 5.2 小说章节。GET novelchapters
  Future<dynamic> getNovelChapters(String id) =>
      _c.get('novelchapters', <String, dynamic>{'id': id}).then((r) => r.data);

  /// 5.3 小说搜索。GET search_novels
  Future<dynamic> searchNovels(String query, int page) =>
      _c.get('search_novels', <String, dynamic>{'search_query': query, 'page': page})
          .then((r) => r.data);

  /// 5.4 小说点赞（需登录）。POST like
  Future<dynamic> likeNovel(Map<String, dynamic> params) =>
      _c.postForm('like', params).then((r) => r.data);

  /// 5.4 小说评论（需登录）。POST comment
  Future<dynamic> commentNovel(Map<String, dynamic> params) =>
      _c.postForm('comment', params).then((r) => r.data);

  /// 5.5 小说收藏列表（需登录）。GET novel_favorites
  Future<dynamic> getNovelFavorites({int page = 1}) =>
      _c.get('novel_favorites', <String, dynamic>{'page': page})
          .then((r) => r.data);

  /// 5.5 添加小说收藏（需登录）。POST novel_favorites
  Future<dynamic> addNovelFavorites(Map<String, dynamic> params) =>
      _c.postForm('novel_favorites', params).then((r) => r.data);

  /// 5.5 编辑小说收藏夹（需登录）。POST novel_favorites_folder
  Future<dynamic> editNovelFavorites(Map<String, dynamic> params) =>
      _c.postForm('novel_favorites_folder', params).then((r) => r.data);

  /// 5.6 小说 J 币购买（需登录）。POST coin_buy_nc
  Future<dynamic> buyNovelWithCoin(Map<String, dynamic> params) =>
      _c.postForm('coin_buy_nc', params).then((r) => r.data);

  /// 5.7 游戏分类。GET allgames（无参数形态）
  Future<dynamic> getGamesCategories() => _c.get('allgames').then((r) => r.data);

  /// 5.8 游戏列表。GET allgames（带参数形态）
  Future<dynamic> getGamesList(
          {int page = 1, String search = '', String category = ''}) =>
      _c.get('allgames', <String, dynamic>{
        'page': page,
        if (search.isNotEmpty) 'search': search,
        if (category.isNotEmpty) 'category': category,
      }).then((r) => r.data);

  /// 5.9 游戏详情。GET game/{id}
  Future<dynamic> getGameInfo(String id) =>
      _c.get('game/$id').then((r) => r.data);

  /// 5.10 视频列表。GET videos
  Future<dynamic> getVideosList(
          {int page = 1, String searchQuery = '', String videoType = ''}) =>
      _c.get('videos', <String, dynamic>{
        'page': page,
        if (searchQuery.isNotEmpty) 'search_query': searchQuery,
        if (videoType.isNotEmpty) 'video_type': videoType,
      }).then((r) => r.data);

  /// 5.11 最新 hanime。GET latest_hanime
  Future<dynamic> getLatestHanime() =>
      _c.get('latest_hanime').then((r) => r.data);

  /// 5.11 视频详情。GET video
  Future<dynamic> getVideoInfo(Map<String, dynamic> params) =>
      _c.get('video', params).then((r) => r.data);

  /// 5.11 baitu token。GET baitu-create-token
  Future<dynamic> getBaituToken() =>
      _c.get('baitu-create-token').then((r) => r.data);

  /// 5.12 博客列表。GET blogs
  Future<dynamic> getBlogsList({int page = 1}) =>
      _c.get('blogs', <String, dynamic>{'page': page}).then((r) => r.data);

  /// 5.12 博客详情。GET blog
  Future<dynamic> getBlogInfo(String id) =>
      _c.get('blog', <String, dynamic>{'id': id}).then((r) => r.data);

  // ===================================================================
  // 任务域 TaskService（21 个方法：签到 / 任务 / J币 / 去广告 / 通知 / 追更）
  // ===================================================================

  /// 6.1 每日任务信息（需登录）。GET daily
  Future<dynamic> getDaily(String userId) =>
      _c.get('daily', <String, dynamic>{'user_id': userId}).then((r) => r.data);

  /// 6.2 每日签到（需登录）。POST daily_chk
  Future<dynamic> dailyCheckIn() => _c.postForm('daily_chk').then((r) => r.data);

  /// 6.3 签到选项列表（需登录）。GET daily_list
  Future<dynamic> getDailyList(String userId) =>
      _c.get('daily_list', <String, dynamic>{'user_id': userId})
          .then((r) => r.data);

  /// 6.3 签到筛选（需登录）。POST daily_list/filter
  Future<dynamic> getDailyListFilter(dynamic data) =>
      _c.postForm('daily_list/filter', <String, dynamic>{'data': data?.toString() ?? ''})
          .then((r) => r.data);

  /// 6.4 任务列表（需登录）。GET tasks
  Future<dynamic> getTasks({String type = '', String filter = ''}) =>
      _c.get('tasks', <String, dynamic>{
        if (type.isNotEmpty) 'type': type,
        if (filter.isNotEmpty) 'filter': filter,
      }).then((r) => r.data);

  /// 6.4 领取/提交任务（需登录）。POST tasks
  Future<dynamic> changeTasks(Map<String, dynamic> params) =>
      _c.postForm('tasks', params).then((r) => r.data);

  /// 6.5 J 币兑换（需登录）。POST coin
  Future<dynamic> tasksBuy(Map<String, dynamic> params) =>
      _c.postForm('coin', params).then((r) => r.data);

  /// 6.6 J 币购买漫画（需登录）。POST coin_buy_comics
  Future<dynamic> buyComicWithCoin(String id) =>
      _c.postForm('coin_buy_comics', <String, dynamic>{'id': id})
          .then((r) => r.data);

  /// 6.7 J 币充值（需登录）。POST coin_buy_charge
  Future<dynamic> coinBuyCharge() =>
      _c.postForm('coin_buy_charge').then((r) => r.data);

  /// 6.8 购买去广告（需登录）。POST ad_free
  Future<dynamic> adFree(Map<String, dynamic> params) =>
      _c.postForm('ad_free', params).then((r) => r.data);

  /// 6.8 支付信息（需登录）。GET payment
  Future<dynamic> adFreePay(Map<String, dynamic> params) =>
      _c.get('payment', params).then((r) => r.data);

  /// 6.9 通知列表（需登录）。GET notifications
  Future<dynamic> getNotifications({int page = 1}) =>
      _c.get('notifications', <String, dynamic>{'page': page})
          .then((r) => r.data);

  /// 6.9 操作通知（需登录）。POST notifications
  Future<dynamic> postNotifications(Map<String, dynamic> params) =>
      _c.postForm('notifications', params).then((r) => r.data);

  /// 6.10 未读通知数（需登录）。GET notifications/unreadCount
  Future<dynamic> getUnreadCount() =>
      _c.get('notifications/unreadCount').then((r) => r.data);

  /// 6.11 追更状态查询（需登录）。GET album_sertracking
  Future<dynamic> sertrackGet(String id) =>
      _c.get('album_sertracking', <String, dynamic>{'id': id})
          .then((r) => r.data);

  /// 6.11 设置/取消追更（需登录）。POST album_sertracking
  Future<dynamic> sertrackPost(String id) =>
      _c.postForm('album_sertracking', <String, dynamic>{'id': id})
          .then((r) => r.data);

  /// 6.11 追更列表（需登录）。POST album_tracking
  Future<List<SearchAlbum>> getTrackList(int page) async {
    final r = await _c.postForm('album_tracking', <String, dynamic>{'page': page});
    return SearchAlbum.listFrom(r.data);
  }

  /// 6.12 标签屏蔽查询（需登录）。GET tag_block
  Future<dynamic> getTagBlock() => _c.get('tag_block').then((r) => r.data);

  /// 6.12 设置标签屏蔽（需登录，全站唯一 JSON body）。POST tag_block
  Future<dynamic> setTagBlock(List<String> tags) =>
      _c.postJson('tag_block', <String, dynamic>{'tags': tags}).then((r) => r.data);

  /// 6.13 意见反馈。GET support_report
  Future<dynamic> supportReport(String action, String srid) =>
      _c.get('support_report', <String, dynamic>{'action': action, 'srid': srid})
          .then((r) => r.data);

  /// 6.13 错误日志上报。POST error_log
  Future<dynamic> errorLog(Map<String, dynamic> params) =>
      _c.postForm('error_log', params).then((r) => r.data);

  // ===================================================================
  // 其它域 MiscService（广告 3 + 创作者 5 + 逃生舱 3）
  // ===================================================================

  /// 7.1 广告横幅。GET advertise
  Future<dynamic> getAdvertise(String group, String v) =>
      _c.get('advertise', <String, dynamic>{'type': 'img', 'group': group, 'v': v})
          .then((r) => r.data);

  /// 7.2 封面广告（固定密钥解密）。GET advertise_all
  Future<dynamic> getAdContentCover(String ipcountry, String v) =>
      _c.get('advertise_all', <String, dynamic>{'ipcountry': ipcountry, 'v': v})
          .then((r) => r.data);

  /// 7.2 全量广告（固定密钥解密）。GET ad_content_all
  Future<dynamic> getAdContentAll(String ipcountry, String v) =>
      _c.get('ad_content_all', <String, dynamic>{'ipcountry': ipcountry, 'v': v})
          .then((r) => r.data);

  /// 7.3 创作者作者信息。GET creator_author
  Future<dynamic> getCreatorAuthor(Map<String, dynamic> params) =>
      _c.get('creator_author', params).then((r) => r.data);

  /// 7.3 创作者作品列表。GET creator_work
  Future<dynamic> getCreatorWork(Map<String, dynamic> params) =>
      _c.get('creator_work', params).then((r) => r.data);

  /// 7.3 创作者作品详情。GET creator_author_work
  Future<dynamic> getCreatorAuthorWork(Map<String, dynamic> params) =>
      _c.get('creator_author_work', params).then((r) => r.data);

  /// 7.3 创作者作品信息。GET creator_work_info
  Future<dynamic> getCreatorWorkInfo(String id) =>
      _c.get('creator_work_info', <String, dynamic>{'id': id}).then((r) => r.data);

  /// 7.3 创作者作品信息详情。GET creator_work_info_detail
  Future<dynamic> getCreatorWorkInfoDetail(String id) =>
      _c.get('creator_work_info_detail', <String, dynamic>{'id': id})
          .then((r) => r.data);

  // ---------- 逃生舱（通用未封装端点） ----------

  /// 7.4 通用 GET。
  Future<JmResponse> miscGet(String path,
          [Map<String, dynamic> params = const <String, dynamic>{}]) =>
      _c.get(path, params);

  /// 7.4 通用 POST 表单。
  Future<JmResponse> miscPost(String path,
          [Map<String, dynamic> params = const <String, dynamic>{}]) =>
      _c.postForm(path, params);

  /// 7.4 通用 POST JSON。
  Future<JmResponse> miscPostJson(String path, Object payload) =>
      _c.postJson(path, payload);
}
