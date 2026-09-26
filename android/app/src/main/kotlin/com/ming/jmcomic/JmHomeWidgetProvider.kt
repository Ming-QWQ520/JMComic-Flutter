package com.ming.jmcomic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * 桌面小组件（4x2）：用户页 + 单部随机推荐。
 *
 * 机制（按需求）：
 * - ⟳ 点击一次 = 原生请求一部随机推荐并替换显示，再点一次继续请求
 *   （不预取一批，[JmWidgetApi.fetchRandomAlbums] limit=1）；
 *   系统每 30 分钟的 APPWIDGET_UPDATE 同样触发一次原生刷新；
 * - 第 0 页 = 用户页（名称/收藏/J币/经验，点击翻到随机推荐页）；
 *   第 1 页 = 随机推荐（封面/名称/JM号，点击打开详情，◀ 返回用户页）；
 * - RemoteViews 不支持触摸手势（横滑会被桌面拦截换屏），
 *   用「点击用户页翻页」代替左右滑动；
 * - 封面按 albumId 磁盘缓存（widget 进程短命，内存缓存无效），
 *   网络中断自动重试，解决"经常无法显示封面"。
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
        val mgr = AppWidgetManager.getInstance(context)
        val allIds = mgr.getAppWidgetIds(
            ComponentName(context, JmHomeWidgetProvider::class.java)
        )
        val ids = intent.getIntArrayExtra(EXTRA_APPWIDGET_IDS)?.takeIf {
            it.isNotEmpty()
        } ?: allIds
        when (intent.action) {
            ACTION_NEXT_PAGE -> {
                // 用户页 → 随机推荐页（点击用户页代替滑动）
                for (id in ids) flipTo(context, mgr, id, 1)
            }
            ACTION_PREV_PAGE -> {
                // ◀ 返回用户页
                for (id in ids) flipTo(context, mgr, id, 0)
            }
            ACTION_OPEN_RANDOM -> {
                val albumId = intent.getStringExtra(EXTRA_ALBUM_ID)
                openAppWithAction(context, "random", albumId)
            }
            ACTION_REFRESH_RANDOM, AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                // ⟳ / 系统周期更新：原生请求一部随机推荐（不进 APP）。
                // goAsync 保持进程存活直到网络请求完成。
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

    /// 渲染 widget：填充用户页与随机推荐页（静态子页按 id 填充）。
    private fun updateWidget(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.jm_widget_layout)
        val prefs = prefs(context)
        val albums = readAlbums(prefs)
        val album = albums.optJSONObject(0)

        // 底部操作行：◀ 返回用户页 + 页码 + ⟳ 换一部
        val ids = intArrayOf(widgetId)
        views.setOnClickPendingIntent(
            R.id.btnPrev, buildActionPendingIntent(context, ACTION_PREV_PAGE, ids)
        )
        views.setOnClickPendingIntent(
            R.id.btnRefresh,
            buildActionPendingIntent(context, ACTION_REFRESH_RANDOM, ids)
        )

        // ---- 用户页（第 0 页）----
        val name = prefs.getString(KEY_USER_NAME, "未登录") ?: "未登录"
        val fav = prefs.getString(KEY_USER_FAV, null) ?: "-"
        val coin = prefs.getString(KEY_USER_COIN, null) ?: "-"
        val exp = prefs.getString(KEY_USER_EXP, null) ?: "-"
        views.setTextViewText(R.id.userName, name)
        views.setTextViewText(R.id.userStats, "收藏 $fav · J币 $coin · 经验 $exp")
        views.setTextViewText(
            R.id.userSubtitle,
            if (name == "未登录") "点击查看随机推荐 · 登录后显示数据" else "点击查看随机推荐"
        )
        views.setOnClickPendingIntent(
            R.id.pageUser,
            buildActionPendingIntent(context, ACTION_NEXT_PAGE, IntArray(0))
        )

        // ---- 随机推荐页（第 1 页）----
        if (album != null) {
            val albumId = album.optString("id", "")
            val coverUrl = album.optString("coverUrl", "")
            views.setTextViewText(
                R.id.albumName,
                album.optString("name", "").ifEmpty { "随机推荐" }
            )
            views.setTextViewText(R.id.albumJmId, "JM: $albumId")
            // 磁盘缓存命中直接给图，未命中后台下载（成功后重绘）
            if (albumId.isNotEmpty()) {
                val bmp = JmWidgetApi.peekCoverBitmap(context, albumId)
                if (bmp != null) {
                    views.setImageViewBitmap(R.id.albumCover, bmp)
                }
            }
            views.setOnClickPendingIntent(
                R.id.pageComic,
                buildActionPendingIntent(
                    context, ACTION_OPEN_RANDOM, ids, albumId
                )
            )
        } else {
            views.setTextViewText(R.id.albumName, "暂无随机推荐")
            views.setTextViewText(R.id.albumJmId, "点 ⟳ 换一部")
        }

        val index = prefs.getInt(KEY_PAGE_INDEX + widgetId, 0).coerceIn(0, 1)
        views.setTextViewText(
            R.id.pageIndex,
            if (index == 0) "1/2 · 用户" else "2/2 · 随机推荐"
        )
        views.setDisplayedChild(R.id.flipper, index)
        mgr.updateAppWidget(widgetId, views)

        // 当前在随机推荐页且封面未命中磁盘缓存时，后台下载（成功后重绘）
        if (index == 1 && album != null) {
            val albumId = album.optString("id", "")
            val coverUrl = album.optString("coverUrl", "")
            if (albumId.isNotEmpty() &&
                JmWidgetApi.peekCoverBitmap(context, albumId) == null
            ) {
                downloadAndSetCover(context, mgr, widgetId, albumId, coverUrl)
            }
        }
    }

    /// 翻到指定页（0=用户页，1=随机推荐页），持久化后重绘。
    private fun flipTo(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        page: Int,
    ) {
        prefs(context).edit().putInt(KEY_PAGE_INDEX + widgetId, page).apply()
        updateWidget(context, mgr, widgetId)
    }

    /// 原生拉取一部随机推荐（不进 APP）：成功则落盘、翻到随机推荐页重绘。
    private fun refreshRandomFromApi(
        context: Context,
        mgr: AppWidgetManager,
    ) {
        val fetched = JmWidgetApi.fetchRandomAlbums(limit = 1) ?: return
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
        if (albums.isEmpty()) return
        saveAlbums(context, albums)
        mainHandler.post { updateAll(context, mgr, showComic = true) }
    }

    // ------------------------------------------------------------------
    // 工具（prefs / readAlbums / saveAlbums 定义在 companion，
    // 实例方法与静态入口共用；companion 内不可访问实例私有成员）
    // ------------------------------------------------------------------

    private fun updateAll(
        context: Context,
        mgr: AppWidgetManager,
        showComic: Boolean = false,
    ) {
        val comp = ComponentName(context, JmHomeWidgetProvider::class.java)
        for (id in mgr.getAppWidgetIds(comp)) {
            // 刷新后直接展示新的随机推荐（⟳ 的预期行为）
            prefs(context).edit()
                .putInt(KEY_PAGE_INDEX + id, if (showComic) 1 else 0).apply()
            updateWidget(context, mgr, id)
            // 刷新后立即预取封面（磁盘缓存），避免先渲染占位
            val album = readAlbums(prefs(context)).optJSONObject(0)
            val albumId = album?.optString("id", "") ?: ""
            if (albumId.isNotEmpty() &&
                JmWidgetApi.peekCoverBitmap(context, albumId) == null
            ) {
                val widgetId = id
                Thread {
                    val bmp = JmWidgetApi.fetchCoverBitmap(
                        context, albumId, album?.optString("coverUrl", "") ?: ""
                    )
                    if (bmp != null) {
                        mainHandler.post {
                            try {
                                if (prefs(context)
                                    .getInt(KEY_PAGE_INDEX + widgetId, 0) == 1
                                ) {
                                    updateWidget(context, mgr, widgetId)
                                }
                            } catch (_: Exception) {
                            }
                        }
                    }
                }.start()
            }
        }
    }

    /// 后台下载封面（磁盘缓存），成功且仍停留在随机推荐页时重绘。
    private fun downloadAndSetCover(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        albumId: String,
        coverUrl: String,
    ) {
        Thread {
            val bmp = JmWidgetApi.fetchCoverBitmap(context, albumId, coverUrl)
                ?: return@Thread
            mainHandler.post {
                try {
                    if (prefs(context).getInt(KEY_PAGE_INDEX + widgetId, 0) == 1) {
                        updateWidget(context, mgr, widgetId)
                    }
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    /// JSONArray 便捷遍历
    private fun JSONArray.iterable(): List<JSONObject> {
        val out = ArrayList<JSONObject>(length())
        for (i in 0 until length()) {
            optJSONObject(i)?.let { out.add(it) }
        }
        return out
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
            if (ids.isNotEmpty()) putExtra(EXTRA_APPWIDGET_IDS, ids)
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
        const val KEY_USER_FAV = "user_fav"
        const val KEY_USER_COIN = "user_coin"
        const val KEY_USER_EXP = "user_exp"
        const val KEY_PAGE_INDEX = "page_index_"
        const val KEY_RANDOM_ALBUMS = "random_albums"

        const val ACTION_NEXT_PAGE = "com.ming.jmcomic.widget.NEXT_PAGE"
        const val ACTION_PREV_PAGE = "com.ming.jmcomic.widget.PREV_PAGE"
        const val ACTION_OPEN_RANDOM = "com.ming.jmcomic.widget.OPEN_RANDOM"

        /// 刷新：原生拉取一部随机推荐（留在桌面，不进 APP）
        const val ACTION_REFRESH_RANDOM = "com.ming.jmcomic.widget.REFRESH_RANDOM"

        const val EXTRA_APPWIDGET_IDS = "appwidget_ids"
        const val EXTRA_ALBUM_ID = "album_id"

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

        /// 供 Flutter 端调用：写入用户信息卡（名称/收藏/J币/经验）
        fun writeUserCard(
            context: Context,
            name: String?,
            favorites: String,
            coin: String,
            exp: String,
        ) {
            prefs(context).edit()
                .putString(KEY_USER_NAME, name ?: "未登录")
                .putString(KEY_USER_FAV, favorites)
                .putString(KEY_USER_COIN, coin)
                .putString(KEY_USER_EXP, exp)
                .apply()
            redraw(context)
        }

        /// 供 Flutter 端调用：写入一部随机推荐（冷启动预填）。
        /// 只写数据不翻页（保持默认的用户页）。
        fun writeRandomAlbums(context: Context, albums: List<Map<String, Any>>) {
            saveAlbums(context, albums)
            redraw(context)
        }

        /// 重绘全部 widget（保持当前页码）。
        private fun redraw(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val comp = ComponentName(context, JmHomeWidgetProvider::class.java)
            for (id in mgr.getAppWidgetIds(comp)) {
                JmHomeWidgetProvider().updateWidget(context, mgr, id)
            }
        }
    }
}
