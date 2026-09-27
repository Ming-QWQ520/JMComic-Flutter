package com.ming.jmcomic

import android.Manifest
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StrictMode
import android.os.SystemClock
import android.view.KeyEvent
import android.view.WindowManager
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
 * - 打开文件夹：弹出系统「打开建议」选择器。先用 queryIntentActivities
 *   枚举能打开目录的管理器（SAF content:// + file:// 各 MIME 形状），
 *   每个管理器构造成显式意图经 EXTRA_INITIAL_INTENTS 置顶——面板
 *   选项数 ≥2，规避部分 OEM ROM"单匹配直接打开"的行为（实测 vivo
 *   上表现为不弹面板直开系统文件管理器）；全部失败时退回 SAF 目录
 *   选择器 / 系统"下载"管理器。
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

        // 调研结论：部分 OEM ROM（vivo 等）在 chooser 目标意图仅解析出
        // 一个应用时会抑制选择面板、直接打开该应用——上一版 SAF
        // content:// 主意图只有系统"文件"能处理，表现为"直接打开系统
        // 的文件管理器"。百分百弹出「打开建议」的做法：先用
        // queryIntentActivities 枚举设备上所有能打开目录的管理器
        //（manifest <queries> 已声明各形状），把每个管理器构造成显式
        // 意图（setComponent）经 EXTRA_INITIAL_INTENTS 置顶——面板中
        // 选项数 ≥2，任何 ROM 都会正常弹出选择面板。
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

        // 候选形状：首条作为 chooser 主意图，其余用于枚举置顶项。
        val probes = ArrayList<Pair<Uri, String>>()
        if (safDocUri != null) {
            probes.add(Pair(
                safDocUri,
                android.provider.DocumentsContract.Document.MIME_TYPE_DIR
            ))
        }
        for (mime in listOf(
            "resource/directory",          // MT 管理器等第三方注册的形状
            "resource/folder",
            "vnd.android.document/directory"
        )) {
            probes.add(Pair(fileUri, mime))
        }

        val target = Intent(Intent.ACTION_VIEW).apply {
            val first = probes.first()
            setDataAndType(first.first, first.second)
            addFlags(grantFlags or Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        // 主意图的处理程序由 chooser 正常解析展示，不进置顶列表，
        // 避免面板出现重复项。
        val targetResolvers = HashSet<android.content.ComponentName>()
        try {
            for (ri in packageManager.queryIntentActivities(target, 0)) {
                val info = ri.activityInfo ?: continue
                targetResolvers.add(
                    android.content.ComponentName(info.packageName, info.name)
                )
            }
        } catch (_: Exception) {
        }

        // 把其余管理器逐个构造成显式意图置顶，保证系统"文件"与
        // MT 管理器等同时出现在「打开建议」中。
        val initials = LinkedHashMap<android.content.ComponentName, Intent>()
        for (i in 1 until probes.size) {
            val uri = probes[i].first
            val mime = probes[i].second
            val probe = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(grantFlags)
            try {
                for (ri in packageManager.queryIntentActivities(probe, 0)) {
                    val info = ri.activityInfo ?: continue
                    val cn = android.content.ComponentName(
                        info.packageName, info.name
                    )
                    if (targetResolvers.contains(cn) || initials.containsKey(cn)) {
                        continue
                    }
                    initials[cn] = Intent(Intent.ACTION_VIEW).apply {
                        setComponent(cn)
                        setDataAndType(uri, mime)
                        addFlags(grantFlags)
                    }
                }
            } catch (_: Exception) {
            }
        }

        // 一个管理器都枚举不到（可见性/形状异常）时不弹空面板，
        // 直接走 SAF 目录选择器 / 系统"下载"管理器兜底。
        if (targetResolvers.isEmpty() && initials.isEmpty()) {
            return openSafFallback(path)
        }

        val chooser = Intent.createChooser(target, "打开文件夹").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (initials.isNotEmpty()) {
                putExtra(
                    Intent.EXTRA_INITIAL_INTENTS,
                    initials.values.toTypedArray()
                )
            }
        }
        return try {
            startActivity(chooser)
            true
        } catch (_: Exception) {
            openSafFallback(path)
        }
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
