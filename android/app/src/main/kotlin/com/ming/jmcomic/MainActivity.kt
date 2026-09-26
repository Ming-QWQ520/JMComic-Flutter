package com.ming.jmcomic

import android.Manifest
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StrictMode
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
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
 * - 打开文件夹：点击"打开下载文件夹"时调用系统文件管理器
 *   （主意图为 SAF content:// 目录 URI + file:// 各 MIME 变体作为
 *   备选意图，一并交给系统选择器——系统"文件管理"与 MT 管理器等
 *   第三方文件管理器都会出现在打开方式中；全部失败时退回系统
 *   "下载"管理器）。
 * - openUrl：调起系统浏览器打开外部链接（B站/GitHub/抖音等）。
 * - shareText：调起系统分享面板（详情页分享按钮）。
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var storageChannel: MethodChannel? = null

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

        // Android 7+ 默认 StrictMode 会拦截 file:// 跨进程暴露。
        // 自定义 chooser 不再依赖 file:// 跨进程暴露（用 explicit launchIntent），
        // 但仍保留放宽策略以兼容旧逻辑。
        try {
            StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
        } catch (_: Exception) {
        }

        // 关键修复：先前用 Intent.createChooser + EXTRA_INITIAL_INTENTS，
        // 部分系统 ROM（vivo/小米/华为等定制 OS）会合并或丢弃 INITIAL_INTENTS，
        // 导致只显示系统"文件"或一两个应用，MT 管理器、Solid Explorer
        // 等第三方文件管理器不在列表中。
        //
        // 新方案：主动查询 PackageManager 枚举所有响应 ACTION_VIEW + file:// +
        // 任一目录 MIME 的应用，按 packageName 去重后用自定义 AlertDialog 列出，
        // 每个应用一条目，确保用户能看到所有已安装的文件管理器。
        val fileUri = Uri.fromFile(dir)
        val mimeTypes = listOf(
            android.provider.DocumentsContract.Document.MIME_TYPE_DIR,
            "resource/folder",
            "resource/directory",
            "vnd.android.document/directory"
        )

        val candidates = mutableMapOf<String, ResolveInfo>()
        for (mime in mimeTypes) {
            val it = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val list = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.queryIntentActivities(
                        it, PackageManager.ResolveInfoFlags.of(0L)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.queryIntentActivities(it, 0)
                }
            } catch (_: Exception) {
                emptyList<ResolveInfo>()
            }
            for (info in list) {
                val pkg = info.activityInfo?.packageName ?: continue
                if (pkg == packageName) continue  // 排除自身
                if (pkg !in candidates) candidates[pkg] = info
            }
        }

        // SAF content:// URI 单独查一次：某些 ROM 的系统文件管理器只响应
        // SAF URI（content://com.android.externalstorage.documents/...），
        // 通过 queryIntentActivities 也会命中。
        try {
            toSafInitialUri(path)?.let { docId ->
                val safUri = android.provider.DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents", docId
                )
                val it = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(
                        safUri,
                        android.provider.DocumentsContract.Document.MIME_TYPE_DIR
                    )
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.queryIntentActivities(
                        it, PackageManager.ResolveInfoFlags.of(0L)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.queryIntentActivities(it, 0)
                }
                for (info in list) {
                    val pkg = info.activityInfo?.packageName ?: continue
                    if (pkg == packageName) continue
                    if (pkg !in candidates) candidates[pkg] = info
                }
            }
        } catch (_: Exception) {
        }

        if (candidates.isNotEmpty()) {
            // 1) 多个候选 → 自定义选择对话框，列出全部应用。
            // 2) 单一候选 → 直接 launch。
            if (candidates.size == 1) {
                val info = candidates.values.first()
                return try {
                    val launch = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(fileUri, mimeTypes[0])
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        setClassName(info.activityInfo.packageName, info.activityInfo.name)
                    }
                    startActivity(launch)
                    true
                } catch (_: Exception) {
                    openSafFallback(path)
                }
            }
            return showFolderChooser(path, fileUri, mimeTypes, candidates.values.toList())
        }

        return openSafFallback(path)
    }

    /// 自定义文件夹打开方式选择器：列出所有匹配的应用。
    /// 完全替代 Intent.createChooser + EXTRA_INITIAL_INTENTS——后者在部分
    /// 定制 ROM（vivo/MIUI/EMUI）会丢条目或合并到一两个应用。
    private fun showFolderChooser(
        path: String,
        fileUri: Uri,
        mimeTypes: List<String>,
        candidates: List<ResolveInfo>
    ): Boolean {
        val labels = candidates.map { it.loadLabel(packageManager).toString() }
        val icons = candidates.map {
            try { it.loadIcon(packageManager) } catch (_: Exception) { null }
        }
        val displayLabels = labels.mapIndexed { i, l ->
            if (icons[i] != null) l else l  // 文本兜底（图标在 dialog 适配器里加载）
        }.toTypedArray()

        val builder = AlertDialog.Builder(this)
            .setTitle("使用以下应用打开文件夹")
            .setItems(displayLabels) { _, which ->
                val info = candidates[which]
                try {
                    val launch = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(fileUri, mimeTypes[0])
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        setClassName(info.activityInfo.packageName, info.activityInfo.name)
                    }
                    startActivity(launch)
                } catch (_: Exception) {
                    openSafFallback(path)
                }
            }
            .setNegativeButton("取消") { d, _ -> d.dismiss() }
        try {
            val dialog = builder.create()
            dialog.show()
            return true
        } catch (_: Exception) {
            return openSafFallback(path)
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
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
