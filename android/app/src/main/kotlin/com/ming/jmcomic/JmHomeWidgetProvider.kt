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
 * 桌面小组件：随机推荐轮播。
 *
 * - 每页显示一部随机推荐漫画（封面 + 名称 + JM号），页数 = 缓存数量
 *   （Flutter 端每次拉取一批写入）；点击封面/名称打开对应漫画详情；
 * - 左右翻页：RemoteViews 不支持触摸手势（横滑会被桌面拦截为换屏），
 *   通过底部 ◀ / ▶ 按钮切换（ViewFlipper.setDisplayedChild）；
 * - 刷新：底部 ⟳ 按钮通过 PendingIntent 拉起 APP（jm_action=widget_refresh），
 *   Flutter 端重新请求随机推荐并经 widget channel 写回本组件；
 * - 封面 Bitmap 按 URL 做 LruCache，翻页回看不重复下载；
 *   Bitmap 压缩到 widget 尺寸，避免 RemoteViews "FAILED BINDER TRANSACTION"。
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
        }
    }

    /// 渲染 widget：按缓存的随机推荐列表动态构建 ViewFlipper 子页。
    private fun updateWidget(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.jm_widget_layout)
        val prefs = prefs(context)
        val albums = readAlbums(prefs)

        // 底部操作行：左右翻页 + 刷新（拉起 APP 让 Flutter 拉新数据）
        val ids = intArrayOf(widgetId)
        views.setOnClickPendingIntent(
            R.id.btnPrev, buildActionPendingIntent(context, ACTION_PREV_PAGE, ids)
        )
        views.setOnClickPendingIntent(
            R.id.btnNext, buildActionPendingIntent(context, ACTION_NEXT_PAGE, ids)
        )
        views.setOnClickPendingIntent(
            R.id.btnRefresh, buildOpenAppPendingIntent(context, ACTION_WIDGET_REFRESH)
        )

        if (albums.length() == 0) {
            // 无缓存数据：占位页 + 提示点击刷新
            views.removeAllViews(R.id.flipper)
            val page = RemoteViews(context.packageName, R.layout.jm_widget_page)
            page.setTextViewText(R.id.albumName, "暂无随机推荐")
            page.setTextViewText(R.id.albumId, "点 ⟳ 拉取")
            views.addView(R.id.flipper, page)
            views.setTextViewText(R.id.pageIndex, "-/-")
            mgr.updateAppWidget(widgetId, views)
            return
        }

        val index = prefs.getInt(KEY_PAGE_INDEX + widgetId, 0)
            .coerceIn(0, albums.length() - 1)

        // 动态构建每页（封面/名称/JM号），整页可点击打开对应详情
        views.removeAllViews(R.id.flipper)
        for (album in albums.iterable()) {
            views.addView(R.id.flipper, buildPage(context, widgetId, album))
        }
        views.setTextViewText(R.id.pageIndex, "${index + 1}/${albums.length()}")
        views.setDisplayedChild(R.id.flipper, index)
        mgr.updateAppWidget(widgetId, views)

        // 当前页封面未缓存时后台下载（下载完仅重绘，避免重复下载已缓存页）
        val coverUrl = albums.optJSONObject(index)?.optString("coverUrl", "") ?: ""
        if (coverUrl.isNotEmpty() && coverCache.get(coverUrl) == null) {
            downloadAndSetCover(context, mgr, widgetId, coverUrl, index)
        }
    }

    /// 构建单页 RemoteViews（封面/名称/JM号 + 整页点击打开详情）。
    private fun buildPage(
        context: Context,
        widgetId: Int,
        album: JSONObject,
    ): RemoteViews {
        val page = RemoteViews(context.packageName, R.layout.jm_widget_page)
        page.setTextViewText(R.id.albumName, album.optString("name", ""))
        page.setTextViewText(R.id.albumId, "JM: ${album.optString("id", "")}")
        coverCache.get(album.optString("coverUrl"))?.let {
            page.setImageViewBitmap(R.id.albumCover, it)
        }
        val open = buildActionPendingIntent(
            context, ACTION_OPEN_RANDOM, intArrayOf(widgetId),
            album.optString("id", "")
        )
        page.setOnClickPendingIntent(R.id.pageRoot, open)
        return page
    }

    /// 左右翻页（delta = +1 / -1，环形），持久化页码后整页重绘。
    private fun flipPage(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        delta: Int,
    ) {
        val prefs = prefs(context)
        val n = readAlbums(prefs).length()
        if (n <= 0) return
        val cur = prefs.getInt(KEY_PAGE_INDEX + widgetId, 0)
        val next = ((cur + delta) % n + n) % n
        prefs.edit().putInt(KEY_PAGE_INDEX + widgetId, next).apply()
        updateWidget(context, mgr, widgetId)
    }

    /// 异步下载封面，成功后回主线程重绘（封面已入 LruCache，翻页复用）。
    private fun downloadAndSetCover(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        coverUrl: String,
        index: Int,
    ) {
        Thread {
            val raw = downloadBitmap(coverUrl) ?: return@Thread
            val scaled = scaleForWidget(raw, 86 * 2)
            coverCache.put(coverUrl, scaled)
            mainHandler.post {
                try {
                    val prefs = prefs(context)
                    // 仅当仍停留在拉取时的页码才重绘（避免覆盖用户翻页）
                    if (prefs.getInt(KEY_PAGE_INDEX + widgetId, 0) == index) {
                        updateWidget(context, mgr, widgetId)
                    }
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    // ------------------------------------------------------------------
    // 工具
    // ------------------------------------------------------------------

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun readAlbums(prefs: SharedPreferences): JSONArray = try {
        JSONArray(prefs.getString(KEY_RANDOM_ALBUMS, "[]") ?: "[]")
    } catch (_: Exception) {
        JSONArray()
    }

    /// JSONArray 便捷遍历
    private fun JSONArray.iterable(): List<JSONObject> {
        val out = ArrayList<JSONObject>(length())
        for (i in 0 until length()) {
            optJSONObject(i)?.let { out.add(it) }
        }
        return out
    }

    /// HTTP GET 下载图片转 Bitmap
    private fun downloadBitmap(urlStr: String): Bitmap? {
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 8000
                setRequestProperty("User-Agent", "okhttp/3.12.0")
                setRequestProperty("Accept", "image/*,*/*;q=0.8")
            }
            return BitmapFactory.decodeStream(conn.inputStream)
        } catch (_: Exception) {
            return null
        } finally {
            conn?.disconnect()
        }
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

    /// 构造发广播到自身 receiver 的 PendingIntent（翻页 / 打开详情）
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

        const val ACTION_NEXT_PAGE = "com.ming.jmcomic.widget.NEXT_PAGE"
        const val ACTION_PREV_PAGE = "com.ming.jmcomic.widget.PREV_PAGE"
        const val ACTION_OPEN_RANDOM = "com.ming.jmcomic.widget.OPEN_RANDOM"

        /// 刷新按钮：拉起 APP，由 Flutter 端拉取新一批随机推荐
        const val ACTION_WIDGET_REFRESH = "widget_refresh"

        const val EXTRA_APPWIDGET_IDS = "appwidget_ids"
        const val EXTRA_ALBUM_ID = "album_id"

        /// 封面位图内存缓存（按条目数计；scaled 封面都很小）
        private val coverCache = object : LruCache<String, Bitmap>(24) {
            override fun sizeOf(key: String, value: Bitmap): Int = 1
        }

        /// 供 Flutter 端调用：写入用户名（保留通道兼容；当前布局不展示用户名）
        fun writeUserName(context: Context, name: String?) {
            prefs(context).edit()
                .putString(KEY_USER_NAME, name ?: "未登录").apply()
        }

        /// 供 Flutter 端调用：写入一批随机推荐（JSON 持久化 + 全量重绘）
        fun writeRandomAlbums(context: Context, albums: List<Map<String, Any>>) {
            val arr = JSONArray()
            for (a in albums) {
                arr.put(
                    JSONObject()
                        .put("name", a["name"]?.toString() ?: "")
                        .put("id", a["id"]?.toString() ?: "")
                        .put("coverUrl", a["coverUrl"]?.toString() ?: "")
                )
            }
            prefs(context).edit()
                .putString(KEY_RANDOM_ALBUMS, arr.toString()).apply()
            // 页码收敛 + 通知所有 widget 重绘
            val mgr = AppWidgetManager.getInstance(context)
            val comp = ComponentName(context, JmHomeWidgetProvider::class.java)
            for (id in mgr.getAppWidgetIds(comp)) {
                val p = prefs(context)
                val n = readAlbums(p).length()
                if (n > 0 && p.getInt(KEY_PAGE_INDEX + id, 0) >= n) {
                    p.edit().putInt(KEY_PAGE_INDEX + id, 0).apply()
                }
                JmHomeWidgetProvider().updateWidget(context, mgr, id)
            }
        }
    }
}
