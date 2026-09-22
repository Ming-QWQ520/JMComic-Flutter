package com.ming.jmcomic

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity
 *
 * 额外能力：在阅读器激活时拦截音量键并转发给 Flutter 用于翻页。
 * - Flutter 侧通过 MethodChannel("com.ming.jmcomic/volume") 调用 setEnabled(true/false)
 *   控制拦截开关（仅阅读器页面开启）；
 * - 拦截到 KEYCODE_VOLUME_UP / KEYCODE_VOLUME_DOWN 时调用 "volume"(up/down)，
 *   并返回 true 消费事件，避免系统调节音量。
 */
class MainActivity : FlutterActivity() {

    private var volumeChannel: MethodChannel? = null

    /// 音量键翻页开关（由 Flutter 侧控制，仅阅读器打开时为 true）
    @Volatile
    private var volumeKeysEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ming.jmcomic/volume"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        volumeKeysEnabled = call.argument<Boolean>("enabled") ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeysEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            val dir = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
            volumeChannel?.invokeMethod("volume", dir)
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        volumeChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
