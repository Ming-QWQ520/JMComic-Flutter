/// JMComic 数据模型。
///
/// 服务端字段类型不稳定（数字/字符串混用），统一通过 [_s]/[_i]/[_b] 规范化。
library;

// ---------- 通用类型规范化 ----------

String _s(dynamic v, [String def = '']) {
  if (v == null) return def;
  if (v is String) return v;
  // 服务端部分字段（如 author）可能返回数组：[a, b] 直接 toString()
  // 会渲染成 "[a, b]" 乱码，这里规范为逗号分隔的纯文本。
  if (v is List) {
    return v
        .map((e) => e is Map ? (e['name'] ?? e['tag'] ?? '').toString() : e.toString())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }
  if (v is Map) {
    return (v['name'] ?? v['tag'] ?? '').toString();
  }
  return v.toString();
}

int _i(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final p = int.tryParse(v);
    if (p != null) return p;
    final d = double.tryParse(v);
    if (d != null) return d.toInt();
  }
  return def;
}

bool _b(dynamic v, [bool def = false]) {
  if (v == null) return def;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return def;
}

Map<String, dynamic> _m(dynamic v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

/// 剥离服务端返回文本中的 HTML 标签并解码常见实体。
///
/// 典型场景：评论 content 形如
/// `<div style='flex-direction:row:flex-wrap:wrap:'>[我推荐这本书 1475566]</div>`，
/// 直接展示会把整段 style 代码暴露给用户（旧版样式的 bug）。
/// 这里移除全部标签仅保留纯文本，并处理 &amp; &lt; &gt; &quot; &#39; &nbsp;。
String stripHtmlTags(String raw) {
  if (raw.isEmpty || !raw.contains('<')) {
    return _decodeHtmlEntities(raw);
  }
  // <br> / </p> 等块级标签转换为换行，避免内容粘连。
  var s = raw.replaceAll(
    RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false),
    '\n',
  );
  s = s.replaceAll(
    RegExp(r'</\s*(p|div|li|tr)\s*>', caseSensitive: false),
    '\n',
  );
  s = s.replaceAllMapped(
    RegExp(r'<[^>]*>'),
    (_) => '',
  );
  s = _decodeHtmlEntities(s);
  // 压缩多余空行。
  s = s
      .split('\n')
      .map((l) => l.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return s;
}

String _decodeHtmlEntities(String s) {
  if (!s.contains('&')) return s;
  return s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}

/// 将任意值规范化为 `List<Map<String, dynamic>>`。
List<Map<String, dynamic>> listOfMaps(dynamic v) {
  if (v is List) {
    return v.whereType<Map<String, dynamic>>().toList();
  }
  return <Map<String, dynamic>>[];
}

// ---------- 设置 ----------

/// setting 接口响应。
class SettingData {
  SettingData.fromMap(Map<String, dynamic> m)
      : version = _s(m['version']),
        jm3Version = _s(m['jm3_version']),
        ipCountry = _s(m['ipcountry']),
        mainWebHost = _s(m['main_web_host']),
        imgHost = _s(m['img_host']),
        baseUrl = _s(m['base_url']),
        cnBaseUrl = _s(m['cn_base_url']),
        adCacheVersion = _s(m['ad_cache_version']),
        jm3DownloadUrl = _s(m['jm3_download_url']);

  final String version;
  final String jm3Version;
  final String ipCountry;
  final String mainWebHost;
  final String imgHost;
  final String baseUrl;
  final String cnBaseUrl;
  final String adCacheVersion;
  final String jm3DownloadUrl;
}

// ---------- 分类 ----------

/// 子分类。
class SubCategory {
  SubCategory.fromMap(Map<String, dynamic> m)
      : cid = _s(m['CID'] ?? m['cid']),
        name = _s(m['name']),
        slug = _s(m['slug']);

  final String cid;
  final String name;
  final String slug;
}

/// 分类。
class Category {
  Category.fromMap(Map<String, dynamic> m)
      : id = _s(m['id'] ?? m['CID']),
        name = _s(m['name'] ?? m['Name']),
        slug = _s(m['slug']),
        type = _s(m['type']),
        // 不同线路字段名不一致：total / total_albums（缺省时为 0，
        // UI 层会以“点击浏览”兜底而不是误导性地显示“共 0 部作品”）。
        totalAlbums = _s(m['total'] ?? m['total_albums'], '0'),
        subCategories =
            listOfMaps(m['sub_categories']).map(SubCategory.fromMap).toList();

  final String id;
  final String name;
  final String slug;
  final String type;

  /// 作品总数（字符串形态，可能为空 / "0" / null —— 服务端部分分类
  /// 不下发总数，但内容实际存在）。
  final String totalAlbums;

  /// 是否存在可展示的总数（>0 才展示，避免“共 0 部作品”的误导）。
  bool get hasTotal {
    final n = int.tryParse(totalAlbums) ?? 0;
    return n > 0;
  }

  final List<SubCategory> subCategories;
}

/// categories 接口响应。
class CategoriesData {
  CategoriesData.fromMap(Map<String, dynamic> m)
      : categories =
            listOfMaps(m['categories']).map(Category.fromMap).toList();

  final List<Category> categories;
}

// ---------- 漫画 ----------

/// 分类引用。
class CategoryRef {
  CategoryRef.fromMap(dynamic v)
      : id = _s(_m(v)['id']),
        title = _s(_m(v)['title']);

  final String id;
  final String title;
}

/// 章节信息。
class SeriesItem {
  SeriesItem.fromMap(Map<String, dynamic> m)
      : id = _s(m['id']),
        name = _s(m['name']),
        sort = _s(m['sort']);

  final String id;
  final String name;
  final String sort;

  /// 章节展示标题。
  ///
  /// 部分漫画（如 JM1468592）的章节 name 直接是纯数字（"1"、"2"），
  /// 目录里会显示成孤零零的数字；这里统一规范为「第x话」：
  /// name 为空或纯数字时用 name（其次 sort）拼成 第x话，
  /// 否则原样返回（如「番外篇」「最终话」）。
  String get displayTitle {
    final n = name.trim();
    if (n.isEmpty) return '第$sort话';
    if (RegExp(r'^\d+$').hasMatch(n)) return '第$n话';
    return n;
  }
}

/// 关联作品。
class AlbumWorks {
  AlbumWorks.fromMap(Map<String, dynamic> m)
      : id = _s(m['id']),
        name = _s(m['name']);

  final String id;
  final String name;
}

/// 漫画详情（album 接口）。
class Album {
  Album.fromMap(Map<String, dynamic> m)
      : id = _i(m['id']),
        name = _s(m['name']),
        author = _s(m['author']),
        description = _s(m['description']),
        addTime = _s(m['addtime']),
        updateAt = _i(m['update_at']),
        totalViews = _s(m['total_views']),
        totalLikes = _s(m['likes']),
        totalPhotos = _i(m['total_photos']),
        commentTotal = _i(m['comment_total']),
        series = listOfMaps(m['series']).map(SeriesItem.fromMap).toList(),
        tags = (m['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        category = CategoryRef.fromMap(m['category']),
        categorySub = CategoryRef.fromMap(m['category_sub']),
        isFavorite = _b(m['is_favorite']),
        liked = _b(m['liked']),
        works = listOfMaps(m['works']).map(AlbumWorks.fromMap).toList();

  final int id;
  final String name;
  final String author;
  final String description;
  final String addTime;
  final int updateAt;
  final String totalViews;
  final String totalLikes;
  final int totalPhotos;

  /// 评论总数（album 接口 comment_total，部分线路缺省为 0）。
  final int commentTotal;
  final List<SeriesItem> series;
  final List<String> tags;
  final CategoryRef category;
  final CategoryRef categorySub;

  /// 收藏/点赞状态（详情页操作后本地翻转）。
  bool isFavorite;
  bool liked;
  final List<AlbumWorks> works;

  /// 作者规范化（服务端可能返回字符串或数组）。
  String get authorText {
    final a = author.trim();
    return a.isEmpty ? '佚名' : a;
  }
}

/// 章节阅读数据中的图片项。
class ReadImage {
  ReadImage.fromMap(Map<String, dynamic> m)
      : page = _i(m['page']),
        image = _s(m['image']);

  final int page;
  final String image;
}

/// comic_read 接口响应。
class ReadData {
  ReadData.fromMap(Map<String, dynamic> m)
      : id = _i(m['id']),
        scrambleId = _s(m['scramble_id']),
        name = _s(m['name']),
        seriesId = _s(m['series_id']),
        totalPage = _i(m['total_page']),
        images = listOfMaps(m['images']).map(ReadImage.fromMap).toList(),
        isFavorite = _b(m['is_favorite']),
        liked = _b(m['liked']);

  final int id;

  /// 乱序判定阈值（与 album_id 比较决定是否需要还原）。
  final String scrambleId;
  final String name;
  final String seriesId;
  final int totalPage;
  final List<ReadImage> images;
  final bool isFavorite;
  final bool liked;
}

/// 搜索/最新/收藏等列表中的漫画项。
class SearchAlbum {
  SearchAlbum.fromMap(Map<String, dynamic> m)
      : id = _s(m['id'] ?? m['aid']),
        name = _s(m['name']),
        author = _s(m['author']),
        image = _s(m['image']),
        category = CategoryRef.fromMap(m['category']),
        categorySub = CategoryRef.fromMap(m['category_sub']),
        liked = _b(m['liked']),
        isFavorite = _b(m['is_favorite']),
        updateAt = _i(m['update_at']),
        addDate = _s(m['adddate']);

  final String id;
  final String name;
  final String author;
  final String image;
  final CategoryRef category;
  final CategoryRef categorySub;
  final bool liked;
  final bool isFavorite;
  final int updateAt;
  final String addDate;

  /// 从任意形态（Map 或数组项）安全构造。
  static SearchAlbum? tryFrom(dynamic v) {
    if (v is! Map<String, dynamic>) return null;
    return SearchAlbum.fromMap(v);
  }

  /// 从原始列表数据规范化出专辑列表。
  static List<SearchAlbum> listFrom(dynamic v) {
    final out = <SearchAlbum>[];
    if (v is List) {
      for (final item in v) {
        final a = SearchAlbum.tryFrom(item);
        if (a != null) out.add(a);
      }
    } else if (v is Map<String, dynamic>) {
      for (final key in const <String>['list', 'content', 'albums', 'data']) {
        if (v[key] is List) return listFrom(v[key]);
      }
      final a = SearchAlbum.tryFrom(v);
      if (a != null) out.add(a);
    }
    return out;
  }
}

/// search 接口响应。
class SearchData {
  SearchData.fromMap(Map<String, dynamic> m)
      : searchQuery = _s(m['search_query']),
        total = _s(m['total']),
        content = SearchAlbum.listFrom(m['content']);

  final String searchQuery;
  final String total;
  final List<SearchAlbum> content;
}

// ---------- 会员 ----------

/// login 接口响应（字段对齐 qt ParseLogin2）。
class LoginData {
  LoginData.fromMap(Map<String, dynamic> m)
      : id = _s(m['uid'] ?? m['id']),
        username = _s(m['username']),
        email = _s(m['email']),
        photo = _s(m['photo']),
        isVip = _b(m['is_vip']),
        coin = _i(m['coin']),
        exp = _i(m['exp']),
        level = _i(m['level']),
        levelName = _s(m['level_name']),
        gender = _s(m['gender']),
        albumFavorites = _i(m['album_favorites']),
        albumFavoritesMax = _i(m['album_favorites_max']),
        nextLevelExp = _i(m['nextLevelExp']),
        dayAdFree = _b(m['day_ad_free']),
        jwtToken =
            _s(m['jwttoken'] ?? m['jwt_token'] ?? m['JWT_TOKEN']),
        s = _s(m['s'] ?? m['AVS']);

  final String id;
  final String username;
  final String email;
  final String photo;
  final bool isVip;
  final int coin;
  final int exp;
  final int level;

  /// 等级名称（对齐 qt level_name）。
  final String levelName;

  /// 性别（Male/Female）。
  final String gender;

  /// 已用收藏数。
  final int albumFavorites;

  /// 收藏上限。
  final int albumFavoritesMax;

  /// 下一级所需经验。
  final int nextLevelExp;
  final bool dayAdFree;
  final String jwtToken;

  /// AVS Cookie 值。
  final String s;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uid': id,
        'username': username,
        'email': email,
        'photo': photo,
        'is_vip': isVip,
        'coin': coin,
        'exp': exp,
        'level': level,
        'level_name': levelName,
        'gender': gender,
        'album_favorites': albumFavorites,
        'album_favorites_max': albumFavoritesMax,
        'nextLevelExp': nextLevelExp,
        'day_ad_free': dayAdFree,
        'jwttoken': jwtToken,
        's': s,
      };

  static LoginData? fromMapSafe(dynamic v) {
    if (v is! Map<String, dynamic>) return null;
    return LoginData.fromMap(v);
  }
}

// ---------- 评论（对齐 qt ParseBookComment / CommentInfo） ----------

/// 单条评论（含子评论）。
class CommentInfo {
  CommentInfo.fromMap(Map<String, dynamic> m)
      : id = _s(m['CID']),
        uid = _s(m['UID']),
        levelName = _s(_m(m['expinfo'])['level_name']),
        level = _i(_m(m['expinfo'])['level']),
        username = _s(m['username']),
        photo = _s(m['photo']),
        // 服务端 content 可能携带内联 HTML（如推荐卡片 div），
        // 剥离标签后仅展示纯文本，避免前端出现原始样式代码。
        content = stripHtmlTags(_s(m['content'])),
        likes = _i(m['likes']),
        addTime = _s(m['addtime']),
        linkBookName = _s(m['name']),
        linkBookId = _s(m['AID']),
        replys = listOfMaps(m['replys']).map(CommentInfo.fromMap).toList();

  final String id;
  final String uid;
  final String levelName;
  final int level;
  final String username;
  final String photo;
  final String content;
  final int likes;
  final String addTime;
  final String linkBookName;
  final String linkBookId;
  final List<CommentInfo> replys;

  /// 头像相对路径（默认头像返回空）。
  String get headPath {
    if (photo.isEmpty || photo.startsWith('nopic-')) return '';
    return photo;
  }

  /// 按页序排序后的子评论列表。
  List<CommentInfo> get subList => replys;
}

/// forum 接口响应（评论列表）。
class CommentData {
  CommentData.fromMap(Map<String, dynamic> m)
      : total = _i(m['total']),
        list = listOfMaps(m['list']).map(CommentInfo.fromMap).toList();

  final int total;
  final List<CommentInfo> list;

  static CommentData empty() => CommentData.fromMap(<String, dynamic>{});
}

// ---------- 收藏（对齐 qt ParseFavoritesReq2 / FavoriteInfo） ----------

/// 收藏夹。
class FavoriteFolder {
  FavoriteFolder.fromMap(Map<String, dynamic> m)
      : fid = _s(m['FID'] ?? m['fid']),
        name = _s(m['name']);

  final String fid;
  final String name;
}

/// favorite 接口响应。
class FavoriteData {
  FavoriteData.fromMap(Map<String, dynamic> m)
      : total = _i(m['total']),
        count = _i(m['count']),
        bookList = SearchAlbum.listFrom(m['list']),
        folders =
            listOfMaps(m['folder_list']).map(FavoriteFolder.fromMap).toList();

  final int total;
  final int count;
  final List<SearchAlbum> bookList;
  final List<FavoriteFolder> folders;

  static FavoriteData empty() => FavoriteData.fromMap(<String, dynamic>{});
}

// ---------- 首页分区（对齐 qt ParseIndex2 / IndexInfo） ----------

/// 首页 promote 分区（一个分区含一组漫画）。
class IndexBlock {
  IndexBlock.fromMap(Map<String, dynamic> m)
      : title = _s(m['title']),
        id = _s(m['id']),
        slug = _s(m['slug']),
        type = _s(m['type']),
        filterVal = _s(m['filter_val']),
        bookList = SearchAlbum.listFrom(m['content']);

  final String title;
  final String id;
  final String slug;
  final String type;
  final String filterVal;
  final List<SearchAlbum> bookList;

  static List<IndexBlock> listFrom(dynamic v) {
    final out = <IndexBlock>[];
    if (v is List) {
      for (final item in v) {
        if (item is Map<String, dynamic>) out.add(IndexBlock.fromMap(item));
      }
    }
    return out;
  }
}
