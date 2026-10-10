package com.globalagencies.godown_scanner

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.globalagencies.godown_scanner/volume_key"
    private var volumeChannel: MethodChannel? = null
    private var isIntercepting = false
    private var isVolumePressed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        volumeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    isIntercepting = true
                    result.success(true)
                }
                "disable" -> {
                    isIntercepting = false
                    isVolumePressed = false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isIntercepting) {
            val keyCode = event.keyCode
            if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                when (event.action) {
                    KeyEvent.ACTION_DOWN -> {
                        if (!isVolumePressed) {
                            isVolumePressed = true
                            volumeChannel?.invokeMethod("onVolumeKeyDown", null)
                        }
                        return true
                    }
                    KeyEvent.ACTION_UP -> {
                        isVolumePressed = false
                        volumeChannel?.invokeMethod("onVolumeKeyUp", null)
                        return true
                    }
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onPause() {
        super.onPause()
        if (isVolumePressed) {
            isVolumePressed = false
            volumeChannel?.invokeMethod("onVolumeKeyUp", null)
        }
    }
}
