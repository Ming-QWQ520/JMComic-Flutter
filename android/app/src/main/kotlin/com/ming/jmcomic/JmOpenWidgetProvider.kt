package com.ming.jmcomic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * 迷你小组件（1x1）：快速随机入口。
 *
 * 点击 = 拉起 APP（jm_action=random，Flutter 端现场拉取一部随机
 * 推荐并打开详情）。纯入口组件，无网络、无数据。
 */
class JmOpenWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.jm_open_widget)
            val intent = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
                putExtra("jm_action", "random")
            }
            views.setOnClickPendingIntent(
                R.id.openRoot,
                PendingIntent.getActivity(
                    context,
                    10086,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
