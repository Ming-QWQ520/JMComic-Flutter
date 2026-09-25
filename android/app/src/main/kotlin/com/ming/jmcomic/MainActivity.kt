package com.ming.jmcomic

import android.Manifest
import android.app.DownloadManager
import android.content.Intent
import android.content.pm.PackageManager
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
 *   （依次尝试 resource/directory 与 vnd.android.document/directory 意图，
 *   全部失败时退回系统"下载"管理器）。
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

        // 文件夹无法走 FileProvider（其只支持文件），直接以 file:// URI
        // 交给文件管理器。Android 7+ 默认 StrictMode 会拦截 file://
        // 跨进程暴露，这里替换为空策略以放行（仅影响本应用进程）。
        try {
            StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
        } catch (_: Exception) {
        }

        val flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        val uri = Uri.fromFile(dir)

        // 主意图 + 备选意图统一交给系统选择器（createChooser）：
        // 不同文件管理器注册的 MIME 各不相同（resource/directory /
        // vnd.android.document/directory），单发一个意图只能命中
        // 个别应用（如网易云/夸克），选择器则列出全部可用项由用户挑选。
        val primary = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "resource/directory")
            addFlags(flags)
        }
        val extras = listOf(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "vnd.android.document/directory")
                addFlags(flags)
            },
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "resource/folder")
                addFlags(flags)
            }
        )
        val chooser = Intent.createChooser(primary, "选择打开方式").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(Intent.EXTRA_INITIAL_INTENTS, extras.toTypedArray())
        }
        try {
            startActivity(chooser)
            return true
        } catch (_: Exception) {
        }

        // 兜底 1：SAF 目录选择器，直接定位到下载目录
        //（Android 8+ 支持 EXTRA_INITIAL_URI 初始位置提示）。
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

        // 兜底 2：打开系统"下载"管理器
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
