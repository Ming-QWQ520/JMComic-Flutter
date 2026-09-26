package com.ming.jmcomic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import org.json.JSONArray

/**
 * 迷你小组件（2x1）：单部随机推荐。
 *
 * - 点击内容 = 打开当前显示的漫画详情；
 * - ⟳ = 原生请求一部随机推荐并替换显示（不进 APP）；
 * - 与主组件（JmHomeWidgetProvider）共用同一份随机推荐数据
 *   （PREFS / KEY_RANDOM_ALBUMS），封面走 JmWidgetApi 磁盘缓存。
 */
class JmQuickWidgetProvider : AppWidgetProvider() {

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
            ACTION_REFRESH -> {
                val pending = goAsync()
                Thread {
                    try {
                        val fetched =
                            JmWidgetApi.fetchRandomAlbums(limit = 1) ?: return@Thread
                        JmHomeWidgetProvider.writeRandomAlbums(
                            context, toAlbumList(fetched)
                        )
                        mainHandler.post { redraw(context) }
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }

    private fun toAlbumList(fetched: JSONArray): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        for (i in 0 until fetched.length()) {
            val o = fetched.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "name" to o.optString("name", ""),
                    "id" to o.optString("id", ""),
                    "coverUrl" to "",
                )
            )
        }
        return out
    }

    private fun updateWidget(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.jm_quick_widget)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val album = try {
            org.json.JSONArray(
                prefs.getString(JmHomeWidgetProvider.KEY_RANDOM_ALBUMS, "[]") ?: "[]"
            ).optJSONObject(0)
        } catch (_: Exception) {
            null
        }

        if (album != null) {
            val albumId = album.optString("id", "")
            views.setTextViewText(
                R.id.quickName,
                album.optString("name", "").ifEmpty { "随机推荐" }
            )
            views.setTextViewText(R.id.quickJmId, "JM: $albumId")
            if (albumId.isNotEmpty()) {
                val bmp = JmWidgetApi.peekCoverBitmap(context, albumId)
                if (bmp != null) views.setImageViewBitmap(R.id.quickCover, bmp)
            }
            views.setOnClickPendingIntent(
                R.id.quickCover,
                buildOpenPendingIntent(context, albumId)
            )
        } else {
            views.setTextViewText(R.id.quickName, "暂无随机推荐")
            views.setTextViewText(R.id.quickJmId, "点 ⟳ 换一部")
        }
        views.setOnClickPendingIntent(
            R.id.quickRefresh,
            buildRefreshPendingIntent(context)
        )
        mgr.updateAppWidget(widgetId, views)

        // 封面未缓存时后台下载并重绘
        if (album != null) {
            val albumId = album.optString("id", "")
            if (albumId.isNotEmpty() &&
                JmWidgetApi.peekCoverBitmap(context, albumId) == null
            ) {
                Thread {
                    val bmp = JmWidgetApi.fetchCoverBitmap(
                        context, albumId, album.optString("coverUrl", "")
                    )
                    if (bmp != null) {
                        mainHandler.post { redraw(context) }
                    }
                }.start()
            }
        }
    }

    private fun redraw(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val comp = ComponentName(context, JmQuickWidgetProvider::class.java)
        for (id in mgr.getAppWidgetIds(comp)) {
            updateWidget(context, mgr, id)
        }
    }

    private fun buildOpenPendingIntent(context: Context, albumId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("jm_action", "random")
            if (albumId.isNotEmpty()) putExtra("album_id", albumId)
        }
        return PendingIntent.getActivity(
            context,
            ("quick_open$albumId").hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun buildRefreshPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, JmQuickWidgetProvider::class.java).apply {
            action = ACTION_REFRESH
        }
        return PendingIntent.getBroadcast(
            context,
            ACTION_REFRESH.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        const val PREFS = "jm_widget_prefs"
        const val ACTION_REFRESH = "com.ming.jmcomic.widget.QUICK_REFRESH"
    }
}
