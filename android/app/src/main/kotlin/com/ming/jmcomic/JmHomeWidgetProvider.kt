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
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * 桌面小组件：双页（用户页 / 随机推荐），点击切换按钮翻页。
 *
 * 实现要点：
 * - 两个页面在 ViewFlipper 中通过 setDisplayedChild 切换；
 * - 用户页：显示用户名（未登录则显示"未登录"），点击打开 APP；
 * - 随机推荐页：封面 + 名称 + JM号，由 Flutter 端通过 widget bridge
 *   channel 写入 SharedPreferences，widget 端读取并刷新。
 *
 * RemoteViews 不支持复杂手势/动画，左右滑动切换通过点击按钮实现。
 * 异步下载封面图用 Thread + Handler，避免引入 coroutines 依赖。
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
        when (intent.action) {
            ACTION_NEXT_PAGE -> {
                val ids = intent.getIntArrayExtra(EXTRA_APPWIDGET_IDS)
                if (ids != null) {
                    val mgr = AppWidgetManager.getInstance(context)
                    for (id in ids) {
                        flipToNextPage(context, mgr, id)
                    }
                }
            }
            ACTION_OPEN_RANDOM -> {
                val albumId = intent.getStringExtra(EXTRA_ALBUM_ID)
                openAppWithAction(context, "random", albumId)
            }
            ACTION_REFRESH_RANDOM -> {
                val ids = intent.getIntArrayExtra(EXTRA_APPWIDGET_IDS)
                if (ids != null) {
                    val mgr = AppWidgetManager.getInstance(context)
                    for (id in ids) {
                        refreshRandomAlbum(context, mgr, id)
                    }
                }
            }
        }
    }

    /// 渲染当前页（默认是用户页，第 0 页）
    private fun updateWidget(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.jm_widget_layout)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pageIndex = prefs.getInt(KEY_PAGE_INDEX + widgetId, 0)

        // 渲染用户名
        val userName = prefs.getString(KEY_USER_NAME, "未登录") ?: "未登录"
        views.setTextViewText(R.id.userName, userName)
        views.setTextViewText(
            R.id.userSubtitle,
            if (userName == "未登录") "点击登录" else "点击打开 APP"
        )

        // 用户页跳转按钮
        views.setOnClickPendingIntent(
            R.id.btnOpenApp,
            buildOpenAppPendingIntent(context, "user")
        )
        views.setOnClickPendingIntent(
            R.id.userAvatar,
            buildOpenAppPendingIntent(context, "user")
        )
        views.setOnClickPendingIntent(
            R.id.userName,
            buildOpenAppPendingIntent(context, "user")
        )

        // 渲染随机推荐（从缓存）
        val albumName = prefs.getString(KEY_RANDOM_NAME, "随机推荐")
        val albumId = prefs.getString(KEY_RANDOM_ID, "") ?: ""
        views.setTextViewText(R.id.albumName, albumName)
        views.setTextViewText(R.id.albumId, "JM: $albumId")

        // 随机推荐页按钮：刷新下一部
        val ids = intArrayOf(widgetId)
        views.setOnClickPendingIntent(
            R.id.btnNextRandom,
            buildActionPendingIntent(context, ACTION_REFRESH_RANDOM, ids, null)
        )

        // 切到当前页
        views.setDisplayedChild(R.id.flipper, pageIndex)

        mgr.updateAppWidget(widgetId, views)

        // 后台异步刷新随机推荐（包括下载封面）
        refreshRandomAlbum(context, mgr, widgetId)
    }

    /// 切换到下一页（用户页 ↔ 随机推荐页）
    private fun flipToNextPage(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val cur = prefs.getInt(KEY_PAGE_INDEX + widgetId, 0)
        val next = (cur + 1) % 2
        prefs.edit().putInt(KEY_PAGE_INDEX + widgetId, next).apply()
        updateWidget(context, mgr, widgetId)
    }

    /// 从 SharedPreferences 读取随机推荐数据并刷新 widget。
    /// 若缓存有封面 URL，后台下载 Bitmap 后回主线程更新 ImageView。
    private fun refreshRandomAlbum(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val name = prefs.getString(KEY_RANDOM_NAME, null) ?: return
        val id = prefs.getString(KEY_RANDOM_ID, null) ?: return
        val coverUrl = prefs.getString(KEY_RANDOM_COVER_URL, null)

        // 主线程先更新文本
        val views = RemoteViews(context.packageName, R.layout.jm_widget_layout)
        views.setTextViewText(R.id.albumName, name)
        views.setTextViewText(R.id.albumId, "JM: $id")

        // 点击封面/名称打开详情页
        val openIntent = buildActionPendingIntent(
            context, ACTION_OPEN_RANDOM, intArrayOf(widgetId), id
        )
        views.setOnClickPendingIntent(R.id.albumCover, openIntent)
        views.setOnClickPendingIntent(R.id.albumName, openIntent)

        if (coverUrl.isNullOrEmpty()) {
            mgr.updateAppWidget(widgetId, views)
            return
        }

        // 后台线程下载封面
        Thread {
            val bitmap = downloadBitmap(coverUrl)
            if (bitmap != null) {
                // 压缩到适合 widget 显示的尺寸（避免 RemoteViews
                // 因 Bitmap 过大触发 "FAILED BINDER TRANSACTION"）
                val scaled = scaleForWidget(bitmap, 56 * 2) // density 2x
                val views2 =
                    RemoteViews(context.packageName, R.layout.jm_widget_layout)
                views2.setTextViewText(R.id.albumName, name)
                views2.setTextViewText(R.id.albumId, "JM: $id")
                views2.setImageViewBitmap(R.id.albumCover, scaled)
                val openIntent2 = buildActionPendingIntent(
                    context, ACTION_OPEN_RANDOM, intArrayOf(widgetId), id
                )
                views2.setOnClickPendingIntent(R.id.albumCover, openIntent2)
                views2.setOnClickPendingIntent(R.id.albumName, openIntent2)
                mainHandler.post {
                    try {
                        mgr.updateAppWidget(widgetId, views2)
                    } catch (_: Exception) {
                        // RemoteViews 序列化失败时静默
                    }
                }
            }
        }.start()
    }

    /// HTTP GET 下载图片转 Bitmap
    private fun downloadBitmap(urlStr: String): Bitmap? {
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
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

    /// 构造打开 APP 并带 jm_action extra 的 PendingIntent
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

    /// 构造发广播到自身 receiver 的 PendingIntent（用于切页/刷新/打开）
    private fun buildActionPendingIntent(
        context: Context,
        action: String,
        ids: IntArray,
        albumId: String?,
    ): PendingIntent {
        val intent = Intent(context, JmHomeWidgetProvider::class.java).apply {
            this.action = action
            putExtra(EXTRA_APPWIDGET_IDS, ids)
            if (albumId != null) putExtra(EXTRA_ALBUM_ID, albumId)
        }
        return PendingIntent.getBroadcast(
            context,
            (action + (albumId ?: "")).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /// 触发 APP 打开并带 jm_action + album_id
    private fun openAppWithAction(context: Context, action: String, albumId: String?) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("jm_action", action)
            if (albumId != null) putExtra("album_id", albumId)
        }
        context.startActivity(intent)
    }

    companion object {
        const val PREFS_NAME = "jm_widget_prefs"
        const val KEY_USER_NAME = "user_name"
        const val KEY_PAGE_INDEX = "page_index_"
        const val KEY_RANDOM_NAME = "random_album_name"
        const val KEY_RANDOM_ID = "random_album_id"
        const val KEY_RANDOM_COVER_URL = "random_album_cover_url"

        const val ACTION_NEXT_PAGE = "com.ming.jmcomic.widget.NEXT_PAGE"
        const val ACTION_OPEN_RANDOM = "com.ming.jmcomic.widget.OPEN_RANDOM"
        const val ACTION_REFRESH_RANDOM = "com.ming.jmcomic.widget.REFRESH_RANDOM"
        const val EXTRA_APPWIDGET_IDS = "appwidget_ids"
        const val EXTRA_ALBUM_ID = "album_id"

        /// 供 Flutter 端调用：写入用户名（登录/退出时更新 widget）
        fun writeUserName(context: Context, name: String?) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_USER_NAME, name ?: "未登录").apply()
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, JmHomeWidgetProvider::class.java)
            )
            for (id in ids) {
                val views =
                    RemoteViews(context.packageName, R.layout.jm_widget_layout)
                views.setTextViewText(R.id.userName, name ?: "未登录")
                mgr.updateAppWidget(id, views)
            }
        }

        /// 供 Flutter 端调用：写入随机推荐漫画
        fun writeRandomAlbum(
            context: Context,
            name: String,
            id: String,
            coverUrl: String,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putString(KEY_RANDOM_NAME, name)
                putString(KEY_RANDOM_ID, id)
                putString(KEY_RANDOM_COVER_URL, coverUrl)
            }.apply()
            // 通知所有 widget 重绘
            val mgr = AppWidgetManager.getInstance(context)
            val comp = ComponentName(context, JmHomeWidgetProvider::class.java)
            val ids = mgr.getAppWidgetIds(comp)
            for (id_ in ids) {
                val intent = Intent(context, JmHomeWidgetProvider::class.java).apply {
                    action = ACTION_REFRESH_RANDOM
                    putExtra(EXTRA_APPWIDGET_IDS, intArrayOf(id_))
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
