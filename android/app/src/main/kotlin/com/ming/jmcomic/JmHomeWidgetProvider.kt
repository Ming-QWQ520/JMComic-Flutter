package com.ming.jmcomic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 桌面小组件：用户页 + 随机推荐轮播。
 *
 * - 第 0 页 = 用户页（头像 + 用户名，点击拉起 APP）；
 *   第 1..N 页 = 随机推荐漫画（封面 + 名称 + JM号，点击打开详情）；
 * - 左右翻页：RemoteViews 不支持触摸手势（横滑会被桌面拦截为换屏），
 *   通过底部 ◀ / ▶ 按钮循环切换（ViewFlipper.setDisplayedChild）；
 * - 刷新：底部 ⟳ 按钮发广播（ACTION_REFRESH_RANDOM），由原生
 *   [JmWidgetApi] 直接拉取随机推荐并重绘——全程留在桌面，不进 APP；
 *   系统每 30 分钟的 APPWIDGET_UPDATE 同样触发一次原生刷新；
 * - 封面 Bitmap 按 URL 做 LruCache，翻页回看不重复下载；
 *   多图片线路依次尝试；压缩到 widget 尺寸避免 binder 上限。
 */
class JmHomeWidgetProvider : AppWidgetProvider() {

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val ids = intent.getIntArrayExtra(EXTRA_APPWIDGET_IDS)
        val mgr = AppWidgetManager.getInstance(context)
        when (intent.action) {
            ACTION_NEXT_PAGE -> {
                if (ids != null) for (id in ids) flipPage(context, mgr, id, +1)
            }
            ACTION_PREV_PAGE -> {
                if (ids != null) for (id in ids) flipPage(context, mgr, id, -1)
            }
            ACTION_OPEN_RANDOM -> {
                val albumId = intent.getStringExtra(EXTRA_ALBUM_ID)
                openAppWithAction(context, "random", albumId)
            }
            ACTION_REFRESH_RANDOM -> {
                // 桌面端直接刷新（不拉起 APP）：goAsync 保持进程存活
                // 直到网络请求完成（广播返回后进程可能被回收）。
                val pending = goAsync()
                Thread {
                    try {
                        refreshRandomFromApi(context, mgr)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                // 系统周期更新（30 分钟）：顺手原生刷新一次随机推荐
                val pending = goAsync()
                Thread {
                    try {
                        refreshRandomFromApi(context, mgr)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }

    /// 渲染 widget：用户页 + 每部随机推荐一页，动态 addView 进 ViewFlipper。
    private fun updateWidget(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.jm_widget_layout)
        val prefs = prefs(context)
        val albums = readAlbums(prefs)
        val total = totalPages(albums.length())

        // 底部操作行：左右翻页 + 刷新（桌面端原生拉取，不进 APP）
        val ids = intArrayOf(widgetId)
        views.setOnClickPendingIntent(
            R.id.btnPrev, buildActionPendingIntent(context, ACTION_PREV_PAGE, ids)
        )
        views.setOnClickPendingIntent(
            R.id.btnNext, buildActionPendingIntent(context, ACTION_NEXT_PAGE, ids)
        )
        views.setOnClickPendingIntent(
            R.id.btnRefresh,
            buildActionPendingIntent(context, ACTION_REFRESH_RANDOM, ids)
        )

        // 动态填充静态子页：用户页（0）+ 漫画页 1..5（多余页 GONE）
        fillUserPage(views, context)
        for (i in 0 until COMIC_SLOTS) {
            val slot = i + 1
            if (i < albums.length()) {
                val album = albums.optJSONObject(i) ?: continue
                views.setViewVisibility(COMIC_PAGE_IDS[i], android.view.View.VISIBLE)
                views.setTextViewText(
                    COMIC_NAME_IDS[i], album.optString("name", "")
                )
                views.setTextViewText(
                    COMIC_JMID_IDS[i], "JM: ${album.optString("id", "")}"
                )
                val coverUrl = album.optString("coverUrl", "")
                val cacheKey = coverUrl.ifEmpty { album.optString("id", "") }
                coverCache.get(cacheKey)?.let {
                    views.setImageViewBitmap(COMIC_COVER_IDS[i], it)
                }
                views.setOnClickPendingIntent(
                    COMIC_PAGE_IDS[i],
                    buildActionPendingIntent(
                        context, ACTION_OPEN_RANDOM, intArrayOf(widgetId),
                        album.optString("id", "")
                    )
                )
            } else {
                views.setViewVisibility(COMIC_PAGE_IDS[i], android.view.View.GONE)
            }
        }

        val index = prefs.getInt(KEY_PAGE_INDEX + widgetId, 0)
            .coerceIn(0, (total - 1).coerceAtLeast(0))
        views.setTextViewText(R.id.pageIndex, "${index + 1}/$total")
        views.setDisplayedChild(R.id.flipper, index)
        mgr.updateAppWidget(widgetId, views)

        // 当前页是漫画页且封面未缓存时，后台下载（成功后重绘）
        if (index >= 1 && index - 1 < albums.length()) {
            val album = albums.optJSONObject(index - 1)
            val id = album?.optString("id", "") ?: ""
            val coverUrl = album?.optString("coverUrl", "") ?: ""
            if (id.isNotEmpty()) {
                val cacheKey = coverUrl.ifEmpty { id }
                if (coverCache.get(cacheKey) == null) {
                    downloadAndSetCover(context, mgr, widgetId, id, coverUrl, index)
                }
            }
        }
    }

    /// 用户页（头像 + 用户名 + 提示，整页点击拉起 APP）
    private fun fillUserPage(views: RemoteViews, context: Context) {
        val name = prefs(context).getString(KEY_USER_NAME, "未登录") ?: "未登录"
        views.setTextViewText(R.id.userName, name)
        views.setTextViewText(
            R.id.userSubtitle,
            if (name == "未登录") "点击登录 · ◀▶ 看随机推荐" else "点击打开 APP"
        )
        views.setOnClickPendingIntent(
            R.id.pageUser, buildOpenAppPendingIntent(context, "user")
        )
    }

    /// 左右翻页（delta = +1 / -1，环形：用户页 ↔ 各漫画页），持久化后重绘。
    private fun flipPage(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        delta: Int,
    ) {
        val prefs = prefs(context)
        val total = totalPages(readAlbums(prefs).length())
        if (total <= 0) return
        val cur = prefs.getInt(KEY_PAGE_INDEX + widgetId, 0)
        val next = ((cur + delta) % total + total) % total
        prefs.edit().putInt(KEY_PAGE_INDEX + widgetId, next).apply()
        updateWidget(context, mgr, widgetId)
    }

    /// 原生拉取随机推荐（不进 APP）：成功则落盘 + 全量重绘。
    private fun refreshRandomFromApi(
        context: Context,
        mgr: AppWidgetManager,
    ) {
        val fetched = JmWidgetApi.fetchRandomAlbums() ?: return
        // 合并 coverUrl 字段（与 Flutter 端写入格式一致）
        val albums = ArrayList<Map<String, Any>>()
        for (o in fetched.iterable()) {
            albums.add(
                mapOf(
                    "name" to o.optString("name", ""),
                    "id" to o.optString("id", ""),
                    "coverUrl" to "",
                )
            )
        }
        saveAlbums(context, albums)
        mainHandler.post { updateAll(context, mgr) }
    }

    // ------------------------------------------------------------------
    // 工具（prefs / readAlbums / saveAlbums / totalPages 定义在 companion，
    // 实例方法与静态入口共用；companion 内不可访问实例私有成员）
    // ------------------------------------------------------------------

    private fun updateAll(context: Context, mgr: AppWidgetManager) {
        val comp = ComponentName(context, JmHomeWidgetProvider::class.java)
        for (id in mgr.getAppWidgetIds(comp)) {
            val p = prefs(context)
            val total = totalPages(readAlbums(p).length())
            if (total > 0 && p.getInt(KEY_PAGE_INDEX + id, 0) >= total) {
                p.edit().putInt(KEY_PAGE_INDEX + id, 0).apply()
            }
            updateWidget(context, mgr, id)
        }
    }

    /// JSONArray 便捷遍历
    private fun JSONArray.iterable(): List<JSONObject> {
        val out = ArrayList<JSONObject>(length())
        for (i in 0 until length()) {
            optJSONObject(i)?.let { out.add(it) }
        }
        return out
    }

    /// 后台下载封面：无缓存 URL 时按 id 拼 {img}/media/albums/{id}_3x4.jpg，
    /// 多图片线路依次尝试；成功后入缓存并重绘（仍停留在原页才更新）。
    private fun downloadAndSetCover(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        albumId: String,
        coverUrl: String,
        index: Int,
    ) {
        Thread {
            val bitmap = downloadCover(albumId, coverUrl) ?: return@Thread
            val cacheKey = coverUrl.ifEmpty { albumId }
            coverCache.put(cacheKey, bitmap)
            mainHandler.post {
                try {
                    if (prefs(context).getInt(KEY_PAGE_INDEX + widgetId, 0) == index) {
                        updateWidget(context, mgr, widgetId)
                    }
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    /// 下载封面 Bitmap（多线路回退），失败返回 null。
    private fun downloadCover(albumId: String, coverUrl: String): Bitmap? {
        val urls = if (coverUrl.isNotEmpty()) {
            listOf(coverUrl)
        } else {
            JmWidgetApi.IMG_HOSTS.map { host ->
                val h = if (host.endsWith('/')) host.dropLast(1) else host
                "$h/media/albums/${albumId}_3x4.jpg"
            }
        }
        for (u in urls) {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL(u).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 5000
                    readTimeout = 8000
                    setRequestProperty("User-Agent", "okhttp/3.12.0")
                    setRequestProperty("Accept", "image/*,*/*;q=0.8")
                }
                val bmp = BitmapFactory.decodeStream(conn.inputStream)
                if (bmp != null) return scaleForWidget(bmp, 86 * 2)
            } catch (_: Exception) {
            } finally {
                conn?.disconnect()
            }
        }
        return null
    }

    /// 把 Bitmap 缩小到适合 RemoteViews 显示的尺寸（避免 binder 上限）。
    private fun scaleForWidget(src: Bitmap, target: Int): Bitmap {
        val w = src.width
        val h = src.height
        val ratio = if (w >= h) target.toFloat() / w else target.toFloat() / h
        if (ratio >= 1f) return src
        val nw = (w * ratio).toInt().coerceAtLeast(1)
        val nh = (h * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, nw, nh, true)
    }

    /// 构造拉起 APP 并带 jm_action extra 的 PendingIntent
    private fun buildOpenAppPendingIntent(
        context: Context,
        action: String,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("jm_action", action)
        }
        return PendingIntent.getActivity(
            context,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /// 构造发广播到自身 receiver 的 PendingIntent（翻页 / 刷新 / 打开详情）
    private fun buildActionPendingIntent(
        context: Context,
        action: String,
        ids: IntArray,
        albumId: String? = null,
    ): PendingIntent {
        val intent = Intent(context, JmHomeWidgetProvider::class.java).apply {
            this.action = action
            putExtra(EXTRA_APPWIDGET_IDS, ids)
            if (!albumId.isNullOrEmpty()) putExtra(EXTRA_ALBUM_ID, albumId)
        }
        return PendingIntent.getBroadcast(
            context,
            (action + (albumId ?: "")).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /// 触发 APP 打开并带 jm_action + album_id
    private fun openAppWithAction(
        context: Context,
        action: String,
        albumId: String?,
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("jm_action", action)
            if (!albumId.isNullOrEmpty()) putExtra("album_id", albumId)
        }
        context.startActivity(intent)
    }

    companion object {
        const val PREFS_NAME = "jm_widget_prefs"
        const val KEY_USER_NAME = "user_name"
        const val KEY_PAGE_INDEX = "page_index_"
        const val KEY_RANDOM_ALBUMS = "random_albums"

        /// 静态漫画页槽位数（jm_widget_layout.xml 中 pageComic1..5）
        const val COMIC_SLOTS = 5

        val COMIC_PAGE_IDS = intArrayOf(
            R.id.pageComic1, R.id.pageComic2, R.id.pageComic3,
            R.id.pageComic4, R.id.pageComic5,
        )
        val COMIC_COVER_IDS = intArrayOf(
            R.id.albumCover1, R.id.albumCover2, R.id.albumCover3,
            R.id.albumCover4, R.id.albumCover5,
        )
        val COMIC_NAME_IDS = intArrayOf(
            R.id.albumName1, R.id.albumName2, R.id.albumName3,
            R.id.albumName4, R.id.albumName5,
        )
        val COMIC_JMID_IDS = intArrayOf(
            R.id.albumJmId1, R.id.albumJmId2, R.id.albumJmId3,
            R.id.albumJmId4, R.id.albumJmId5,
        )

        const val ACTION_NEXT_PAGE = "com.ming.jmcomic.widget.NEXT_PAGE"
        const val ACTION_PREV_PAGE = "com.ming.jmcomic.widget.PREV_PAGE"
        const val ACTION_OPEN_RANDOM = "com.ming.jmcomic.widget.OPEN_RANDOM"

        /// 刷新：原生拉取随机推荐（留在桌面，不进 APP）
        const val ACTION_REFRESH_RANDOM = "com.ming.jmcomic.widget.REFRESH_RANDOM"

        const val EXTRA_APPWIDGET_IDS = "appwidget_ids"
        const val EXTRA_ALBUM_ID = "album_id"

        /// 封面位图内存缓存（按条目数计；scaled 封面都很小）
        private val coverCache = object : LruCache<String, Bitmap>(24) {
            override fun sizeOf(key: String, value: Bitmap): Int = 1
        }

        private fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        private fun readAlbums(prefs: SharedPreferences): JSONArray = try {
            JSONArray(prefs.getString(KEY_RANDOM_ALBUMS, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }

        private fun saveAlbums(context: Context, albums: List<Map<String, Any>>) {
            val arr = JSONArray()
            for (a in albums) {
                arr.put(
                    JSONObject()
                        .put("name", a["name"]?.toString() ?: "")
                        .put("id", a["id"]?.toString() ?: "")
                        .put("coverUrl", a["coverUrl"]?.toString() ?: "")
                )
            }
            prefs(context).edit().putString(KEY_RANDOM_ALBUMS, arr.toString()).apply()
        }

        /// 页面总数 = 用户页(1) + 随机推荐数
        private fun totalPages(albumCount: Int): Int = albumCount + 1

        /// 供 Flutter 端调用：写入用户名（用户页展示）
        fun writeUserName(context: Context, name: String?) {
            prefs(context).edit()
                .putString(KEY_USER_NAME, name ?: "未登录").apply()
            // 重绘以刷新用户页文案
            val mgr = AppWidgetManager.getInstance(context)
            val comp = ComponentName(context, JmHomeWidgetProvider::class.java)
            val p = prefs(context)
            for (id in mgr.getAppWidgetIds(comp)) {
                if (p.getInt(KEY_PAGE_INDEX + id, 0) == 0) {
                    JmHomeWidgetProvider().updateWidget(context, mgr, id)
                }
            }
        }

        /// 供 Flutter 端调用：写入一批随机推荐（JSON 持久化 + 全量重绘）
        fun writeRandomAlbums(context: Context, albums: List<Map<String, Any>>) {
            saveAlbums(context, albums)
            // 页码收敛 + 通知所有 widget 重绘
            val mgr = AppWidgetManager.getInstance(context)
            val comp = ComponentName(context, JmHomeWidgetProvider::class.java)
            for (id in mgr.getAppWidgetIds(comp)) {
                val p = prefs(context)
                val total = totalPages(albums.size)
                if (p.getInt(KEY_PAGE_INDEX + id, 0) >= total) {
                    p.edit().putInt(KEY_PAGE_INDEX + id, 0).apply()
                }
                JmHomeWidgetProvider().updateWidget(context, mgr, id)
            }
        }
    }
}
