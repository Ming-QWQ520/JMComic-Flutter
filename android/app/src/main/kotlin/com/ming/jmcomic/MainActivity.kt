package com.ming.jmcomic

import android.Manifest
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StrictMode
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MainActivity
 *
 * 额外能力：
 * - 阅读器激活时拦截音量键并转发给 Flutter 用于翻页；
 *   Flutter 侧调用 setEnabled(true/false) 控制开关；
 *   拦截到 KEYCODE_VOLUME_UP/DOWN 时调用 "volume"(up/down) 并消费事件。
 * - 阅读时屏幕常亮：Flutter 侧调用 keepScreenOn(true/false) 控制 FLAG_KEEP_SCREEN_ON。
 * - 存储权限（下载目录 /storage/emulated/0/Download/JM-Flutter）：
 *   - Android 10 及以下：运行时申请 WRITE/READ_EXTERNAL_STORAGE；
 *   - Android 11+：跳转"所有文件访问"（MANAGE_EXTERNAL_STORAGE）系统设置页。
 * - 打开文件夹：应用内自绘「打开方式」列表——枚举能打开目录的管理器
 *   （SAF content:// + file:// 各 MIME 形状），点击后以显式意图直接
 *   启动，不经过系统 ResolverActivity（vivo 等定制 ROM 会把系统选择
 *   器静默改写为直开单个应用，实测三次迭代均被吞，故彻底自绘）；
 *   列表末尾附 SAF 目录选择器兜底，全部失败退回系统"下载"管理器。
 * - openUrl：调起系统浏览器打开外部链接（B站/GitHub/抖音等）。
 * - shareText：调起系统分享面板（详情页分享按钮）。
 */
// FlutterFragmentActivity：local_auth 的 BiometricPrompt 需要
// FragmentActivity 宿主（应用锁指纹/面容/锁屏密码）。
class MainActivity : FlutterFragmentActivity() {

    private var channel: MethodChannel? = null
    private var storageChannel: MethodChannel? = null

    /// native → Flutter 通道引用：jm_action（快捷菜单跳转）/ isAtRoot
    /// （双击退出）必须发到 "com.ming.jmcomic/widget"（Flutter 端
    /// WidgetBridge 在此通道上监听）。此前误用 volume 通道导致无响应。
    private var widgetChannel: MethodChannel? = null

    /// 双击退出：首次返回键弹 Toast 提示，2 秒内再按一次才真正退出。
    /// 用户反馈要求：增加滑动第二次才会退出 APP。
    private var lastBackPressTime: Long = 0
    private val backPressHandler = Handler(Looper.getMainLooper())

    /// 长按图标 shortcut / 桌面小组件点击跳转的 action extra
    private var pendingJmAction: String? = null
    private var pendingAlbumId: String? = null

    /// 音量键翻页开关（由 Flutter 侧控制，仅阅读器打开时为 true）
    @Volatile
    private var volumeKeysEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ming.jmcomic/volume"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        volumeKeysEnabled = call.argument<Boolean>("enabled") ?: false
                        result.success(null)
                    }
                    "keepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        storageChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ming.jmcomic/storage"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasStoragePermission" -> result.success(hasStoragePermission())
                    "ensureStoragePermission" -> result.success(ensureStoragePermission())
                    "openFolder" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(openFolder(path))
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        result.success(openUrl(url))
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(installApk(path))
                    }
                    "shareText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val title = call.argument<String>("title") ?: "分享"
                        result.success(shareText(text, title))
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Widget bridge channel：native → Flutter 的 jm_action
        // （长按图标快捷菜单）与 isAtRoot（双击退出判断）通道，
        // Flutter 端 WidgetBridge 在此监听。
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ming.jmcomic/widget"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingAction" -> {
                        // 取出 shortcut / widget 点击时缓存的 action，
                        // 由 Flutter 端处理后清空
                        val action = pendingJmAction
                        val albumId = pendingAlbumId
                        pendingJmAction = null
                        pendingAlbumId = null
                        val map = mutableMapOf<String, Any?>()
                        map["action"] = action
                        map["albumId"] = albumId
                        result.success(map)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // 注意：jm_action 的分发统一由 onCreate / onNewIntent 负责
        // （configureFlutterEngine 在 super.onCreate 内触发，早于
        // intent extra 的解析，在这里分发会读到 null 或造成重复分发）。
    }

    /// 把 shortcut / widget 跳转 action 通过 widget 通道同步到 Flutter。
    /// Flutter 端 WidgetBridge 在 "com.ming.jmcomic/widget" 上监听 jm_action。
    ///
    /// 冷启动时 Dart 侧可能尚未注册处理器（invokeMethod 返回
    /// notImplemented），带 3 次重试（400ms / 1200ms / 2400ms）。
    private fun dispatchActionToFlutter(action: String, albumId: String?) {
        dispatchActionWithRetry(action, albumId, 0)
    }

    private fun dispatchActionWithRetry(action: String, albumId: String?, attempt: Int) {
        val delay = when (attempt) {
            0 -> 400L
            1 -> 1200L
            else -> 2400L
        }
        backPressHandler.postDelayed({
            widgetChannel?.invokeMethod(
                "jm_action",
                mapOf(
                    "action" to action,
                    "albumId" to (albumId ?: "")
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (attempt < 2) {
                            dispatchActionWithRetry(action, albumId, attempt + 1)
                        }
                    }

                    override fun notImplemented() {
                        if (attempt < 2) {
                            dispatchActionWithRetry(action, albumId, attempt + 1)
                        }
                    }
                }
            )
        }, delay)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 关键时序修复：super.onCreate() 内部就会触发 configureFlutterEngine
        // （其中的 jm_action 分发此时读到的 pendingJmAction 还是 null），
        // 因此必须先解析 intent extra，再调 super——冷启动快捷方式此前
        // 从未分发成功，表现为"点快捷方式进首页"。
        intent?.let { i ->
            val a = i.getStringExtra("jm_action")
            if (a != null) {
                pendingJmAction = a
                pendingAlbumId = i.getStringExtra("album_id")
            }
        }
        super.onCreate(savedInstanceState)
        // 冷启动分发（warm start 走 onNewIntent）。分发后立即清空，
        // 避免 configureFlutterEngine 内的兜底分发造成重复跳转。
        pendingJmAction?.let { a ->
            dispatchActionToFlutter(a, pendingAlbumId)
            pendingJmAction = null
            pendingAlbumId = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // App 在后台时通过 shortcut 跳转会走 onNewIntent
        val action = intent.getStringExtra("jm_action")
        if (action != null) {
            val albumId = intent.getStringExtra("album_id")
            dispatchActionToFlutter(action, albumId)
        }
        setIntent(intent)
    }

    /// 双击返回退出：用户在主页按返回键时，首次提示"再按一次退出"，
    /// 2 秒内再按一次才真正 finish()。在非主页（阅读器/详情页）按返回
    /// 由 Flutter Navigator 处理，不进入此逻辑。
    override fun onBackPressed() {
        // 让 Flutter 优先处理（路由栈非空时由 Navigator pop）
        // 这里通过 widget 通道询问 Flutter 是否在根路由
        widgetChannel?.invokeMethod("isAtRoot", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val atRoot = (result as? Boolean) == true
                if (atRoot) {
                    // 在根路由，启用双击退出
                    val now = SystemClock.uptimeMillis()
                    if (now - lastBackPressTime < 2000) {
                        lastBackPressTime = 0
                        finishAffinity()
                    } else {
                        lastBackPressTime = now
                        Toast.makeText(
                            this@MainActivity,
                            "再按一次退出",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                } else {
                    // 非根路由：交给 Flutter 处理
                    this@MainActivity.superOnBackPressed()
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                // Flutter 未实现 isAtRoot，直接走默认 back
                this@MainActivity.superOnBackPressed()
            }

            override fun notImplemented() {
                this@MainActivity.superOnBackPressed()
            }
        })
    }

    private fun superOnBackPressed() {
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    // ------------------------------------------------------------------
    // 存储权限
    // ------------------------------------------------------------------

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+：需要"所有文件访问"才能在公共下载目录建目录/写文件
            Environment.isExternalStorageManager()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    /// 发起权限申请。异步授权无法立刻返回结果：
    /// - 返回 true 表示已授权；
    /// - 返回 false 表示已发起申请（Android 11+ 跳设置页 / 低版本弹系统对话框），
    ///   Flutter 侧应在用户返回后调用 hasStoragePermission 重新检查。
    private fun ensureStoragePermission(): Boolean {
        if (hasStoragePermission()) return true
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
                )
                intent.data = Uri.parse("package:$packageName")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } else {
                requestPermissions(
                    arrayOf(
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    ),
                    1001
                )
            }
        } catch (_: Exception) {
            // 个别 ROM 限制跳转时静默失败，由 Flutter 侧提示手动授权
        }
        return false
    }

    // ------------------------------------------------------------------
    // 打开文件夹（系统文件管理器）
    // ------------------------------------------------------------------

    private fun openFolder(path: String): Boolean {
        val dir = File(path)
        try {
            if (!dir.exists()) dir.mkdirs()
        } catch (_: Exception) {
        }

        // Android 7+ 默认 StrictMode 会拦截 file:// 跨进程暴露；
        // 目录无法走 FileProvider，这里放宽检测。
        try {
            StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
        } catch (_: Exception) {
        }

        // 彻底方案：不再依赖系统选择器。vivo 等定制 ROM 会把
        // createChooser（含 EXTRA_INITIAL_INTENTS 显式置顶）静默改写成
        // 直开单个应用——系统侧三次迭代均被吞（实测实锤）。这里改为
        // 应用内自绘「打开方式」列表：queryIntentActivities 枚举设备上
        // 能打开目录的管理器（manifest <queries> 已声明各形状），点击
        // 后用显式意图（setComponent）直接启动，全过程不经过系统
        // ResolverActivity，任何 ROM 上行为一致、百分百弹窗。
        val fileUri = Uri.fromFile(dir)
        val grantFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val safDocUri: Uri? = try {
            toSafInitialUri(path)?.let {
                android.provider.DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents", it
                )
            }
        } catch (_: Exception) {
            null
        }

        // 探测形状：优先 SAF content://（管理器可直接定位到该目录），
        // 其次 file:// 各 MIME 变体（MT 管理器等第三方注册的形状）。
        val probes = ArrayList<Pair<Uri, String>>()
        if (safDocUri != null) {
            probes.add(Pair(
                safDocUri,
                android.provider.DocumentsContract.Document.MIME_TYPE_DIR
            ))
        }
        for (mime in listOf(
            "resource/directory",
            "resource/folder",
            "vnd.android.document/directory"
        )) {
            probes.add(Pair(fileUri, mime))
        }

        // 枚举：同一应用只保留第一个命中的形状（SAF 优先，体验最好）。
        val pm = packageManager
        // (应用名, 图标, 启动意图)
        val found = LinkedHashMap<String, Triple<String, android.graphics.drawable.Drawable, Intent>>()
        for ((uri, mime) in probes) {
            val probe = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(grantFlags)
            val infos = try {
                pm.queryIntentActivities(probe, 0)
            } catch (_: Exception) {
                emptyList<ResolveInfo>()
            }
            for (ri in infos) {
                val info = ri.activityInfo ?: continue
                val key = "${info.packageName}/${info.name}"
                if (found.containsKey(key)) continue
                found[key] = Triple(
                    ri.loadLabel(pm).toString(),
                    ri.loadIcon(pm),
                    Intent(Intent.ACTION_VIEW)
                        .setComponent(
                            ComponentName(info.packageName, info.name)
                        )
                        .setDataAndType(uri, mime)
                        .addFlags(grantFlags)
                )
            }
        }

        // MT 管理器未注册任何"打开文件夹"的 intent-filter（调研确认，
        // 这也是它从不出现在系统选择器/任何枚举中的根因），这里为其
        // 固定添加入口：用启动意图打开 MT 主界面，由用户自行导航到
        // 下载目录。已安装才显示。
        try {
            val mtLaunch = pm.getLaunchIntentForPackage("bin.mt.plus")
            if (mtLaunch != null && !found.containsKey("bin.mt.plus")) {
                found["bin.mt.plus#launch"] = Triple(
                    "MT 管理器（打开后请定位到下载目录）",
                    pm.getApplicationIcon("bin.mt.plus"),
                    mtLaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
        } catch (_: Exception) {
        }

        // 一个管理器都枚举不到（可见性/形状异常）时不出空列表，
        // 直接走 SAF 目录选择器 / 系统"下载"管理器兜底。
        if (found.isEmpty()) {
            return openSafFallback(path)
        }
        showOpenWithDialog(found.values.toList())
        return true
    }

    /// 应用内「打开方式」列表：图标 + 应用名逐行排列，点击后以显式
    /// 意图直接启动对应管理器；末尾附一条 SAF 目录选择器兜底（所选
    /// 管理器打不开目录时可用）。
    private fun showOpenWithDialog(
        entries: List<Triple<String, android.graphics.drawable.Drawable, Intent>>,
    ) {
        val density = resources.displayMetrics.density
        val pad = (16 * density).toInt()
        val iconSize = (36 * density).toInt()
        val selector = TypedValue()
        theme.resolveAttribute(
            android.R.attr.selectableItemBackground, selector, true
        )

        val dialog = AlertDialog.Builder(this)
            .setTitle("打开方式")
            .setNegativeButton("取消", null)
            .create()
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        for ((labelText, iconDrawable, launch) in entries) {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(pad, pad / 2, pad, pad / 2)
                isClickable = true
                isFocusable = true
                setBackgroundResource(selector.resourceId)
            }
            val icon = ImageView(this).apply {
                setImageDrawable(iconDrawable)
                layoutParams = LinearLayout.LayoutParams(iconSize, iconSize)
            }
            val label = TextView(this).apply {
                text = labelText
                textSize = 16f
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    1f,
                ).apply { marginStart = (14 * density).toInt() }
            }
            row.addView(icon)
            row.addView(label)
            row.setOnClickListener {
                dialog.dismiss()
                try {
                    startActivity(launch)
                } catch (_: Exception) {
                    Toast.makeText(
                        this@MainActivity, "无法启动该应用", Toast.LENGTH_SHORT
                    ).show()
                }
            }
            list.addView(row)
        }

        // 末尾兜底行：SAF 目录选择器（含初始位置提示）。
        val fallbackRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(pad, pad / 2, pad, pad / 2)
            isClickable = true
            isFocusable = true
            setBackgroundResource(selector.resourceId)
        }
        val fallbackIcon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_manage)
            layoutParams = LinearLayout.LayoutParams(iconSize, iconSize)
        }
        val fallbackLabel = TextView(this).apply {
            text = "其他 · 使用 SAF 目录选择器"
            textSize = 16f
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f,
            ).apply { marginStart = (14 * density).toInt() }
        }
        fallbackRow.addView(fallbackIcon)
        fallbackRow.addView(fallbackLabel)
        fallbackRow.setOnClickListener {
            dialog.dismiss()
            openSafFallback(path)
        }
        list.addView(fallbackRow)

        dialog.setView(ScrollView(this).apply { addView(list) })
        dialog.show()
    }

    /// SAF 目录选择器 + 系统下载管理器 兜底。
    private fun openSafFallback(path: String): Boolean {
        try {
            val saf = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    toSafInitialUri(path)?.let {
                        putExtra(
                            android.provider.DocumentsContract.EXTRA_INITIAL_URI,
                            android.provider.DocumentsContract
                                .buildDocumentUri(
                                    "com.android.externalstorage.documents",
                                    it
                                )
                        )
                    }
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(saf)
            return true
        } catch (_: Exception) {
        }
        return try {
            startActivity(
                Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    // ------------------------------------------------------------------
    // 打开链接（系统浏览器）
    // ------------------------------------------------------------------

    private fun openUrl(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /// 拉起系统安装器安装已下载的更新 APK（经 FileProvider 暴露
    /// 应用专属外部目录下的文件；未授予"安装未知应用"时系统会
    /// 自行引导授权页）。
    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this, "$packageName.fileprovider", file
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK
                )
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    // ------------------------------------------------------------------
    // 系统分享面板
    // ------------------------------------------------------------------

    private fun shareText(text: String, title: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            startActivity(Intent.createChooser(intent, title))
            true
        } catch (_: Exception) {
            false
        }
    }

    /// 把内部存储路径转换为 SAF 的 documentId（如
    /// /storage/emulated/0/Download/JM-Flutter → primary:Download/JM-Flutter）。
    /// 不匹配时返回 null（SAF 打开时不带初始位置）。
    private fun toSafInitialUri(path: String): String? {
        val p = path.trim().trimEnd('/')
        val m = Regex("^/storage/emulated/(\\d+)/(.+)$").find(p) ?: return null
        return if (m.groupValues[1] == "0") {
            "primary:${m.groupValues[2]}"
        } else {
            null
        }
    }

    // ------------------------------------------------------------------
    // 音量键翻页
    // ------------------------------------------------------------------

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeysEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            val dir = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
            channel?.invokeMethod("volume", dir)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        // 按下时已被消费的音量键，抬起阶段同样消费，避免残留系统行为
        if (volumeKeysEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // 运行时权限申请结束，通知 Flutter 侧刷新状态
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            storageChannel?.invokeMethod("storagePermissionResult", granted)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        storageChannel = null
        widgetChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
