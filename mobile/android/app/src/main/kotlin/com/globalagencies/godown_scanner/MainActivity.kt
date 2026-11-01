package com.globalagencies.godown_scanner

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val VOLUME_CHANNEL = "com.globalagencies.godown_scanner/volume_key"
    private val SCANNER_CHANNEL = "com.globalagencies.godown_scanner/scanner"

    private var volumeChannel: MethodChannel? = null
    private var scannerChannel: MethodChannel? = null

    private var isInterceptingVolume = false
    private var isVolumePressed = false

    private var isScannerEnabled = true
    private val scannerBuffer = StringBuilder()
    private var lastKeystrokeTime: Long = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var burstRunnable: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Volume button channel (for hold-to-scan on physical camera triggers)
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL)
        volumeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    isInterceptingVolume = true
                    result.success(true)
                }
                "disable" -> {
                    isInterceptingVolume = false
                    isVolumePressed = false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Hardware scanner channel (native zero-latency interceptor)
        scannerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCANNER_CHANNEL)
        scannerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    isScannerEnabled = call.argument<Boolean>("enabled") ?: true
                    result.success(true)
                }
                "clearBuffer" -> {
                    clearScannerBuffer()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun clearScannerBuffer() {
        burstRunnable?.let { mainHandler.removeCallbacks(it) }
        burstRunnable = null
        scannerBuffer.setLength(0)
        lastKeystrokeTime = 0L
    }

    private fun finalizeScannerBurst() {
        burstRunnable?.let { mainHandler.removeCallbacks(it) }
        burstRunnable = null
        lastKeystrokeTime = 0L

        val raw = scannerBuffer.toString()
        scannerBuffer.setLength(0)

        if (raw.isBlank()) return

        val lines = raw.split(Regex("[\r\n]+"))
        for (line in lines) {
            val clean = line.replace(Regex("[\\x00-\\x1F\\x7F-\\x9F]"), "").trim().uppercase()
            if (clean.length >= 2) {
                runOnUiThread {
                    scannerChannel?.invokeMethod("onBarcodeScanned", clean)
                }
            }
        }
    }

    private fun scheduleBurstCompletion(delayMs: Long) {
        burstRunnable?.let { mainHandler.removeCallbacks(it) }
        burstRunnable = Runnable { finalizeScannerBurst() }
        mainHandler.postDelayed(burstRunnable!!, delayMs)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // A. Volume button interception
        if (isInterceptingVolume) {
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

        // B. Hardware scanner interception
        if (!isScannerEnabled) {
            return super.dispatchKeyEvent(event)
        }

        val keyCode = event.keyCode

        // Allow volume keys to adjust volume when not in volume trigger mode
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        // Consume UP events for scanner keys so trailing events never reach UI
        if (event.action == KeyEvent.ACTION_UP) {
            if (isPotentialScannerKey(keyCode)) {
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        // Handle ACTION_MULTIPLE (sent by some USB wedges or Android barcode drivers)
        if (event.action == KeyEvent.ACTION_MULTIPLE) {
            val characters = event.characters
            if (!characters.isNullOrEmpty()) {
                val now = System.currentTimeMillis()
                if (lastKeystrokeTime != 0L && now - lastKeystrokeTime > 1500) {
                    scannerBuffer.setLength(0)
                }
                lastKeystrokeTime = now
                scannerBuffer.append(characters)
                scheduleBurstCompletion(350)
                return true
            }
        }

        if (event.action != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        // Ignore modifier-only keys (Shift, Ctrl, Alt, CapsLock, NumLock)
        if (isModifierKey(keyCode)) {
            return true
        }

        // Escape: cancel and clear
        if (keyCode == KeyEvent.KEYCODE_ESCAPE) {
            clearScannerBuffer()
            return true
        }

        val now = System.currentTimeMillis()
        if (lastKeystrokeTime != 0L && now - lastKeystrokeTime > 1500) {
            scannerBuffer.setLength(0)
        }

        // Check for Terminator Keys (Enter / Numpad Enter / \n / \r)
        val isTerminator = (keyCode == KeyEvent.KEYCODE_ENTER ||
                keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER ||
                event.unicodeChar == '\n'.code ||
                event.unicodeChar == '\r'.code)

        if (isTerminator) {
            lastKeystrokeTime = now
            scannerBuffer.append('\n')
            // Fast 25ms finalization on Enter
            scheduleBurstCompletion(25)
            return true
        }

        // Extract character
        val char = extractChar(event)
        if (char != null) {
            lastKeystrokeTime = now
            scannerBuffer.append(char)
            // 350ms silence window for scanners without enter or cold-start jitter
            scheduleBurstCompletion(350)
            return true
        }

        return super.dispatchKeyEvent(event)
    }

    private fun isPotentialScannerKey(keyCode: Int): Boolean {
        if (keyCode == KeyEvent.KEYCODE_ENTER || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER) return true
        if (keyCode in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9) return true
        if (keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) return true
        if (keyCode in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9) return true
        if (isModifierKey(keyCode)) return true
        if (keyCode == KeyEvent.KEYCODE_MINUS || keyCode == KeyEvent.KEYCODE_SLASH ||
            keyCode == KeyEvent.KEYCODE_PERIOD || keyCode == KeyEvent.KEYCODE_SPACE ||
            keyCode == KeyEvent.KEYCODE_EQUALS || keyCode == KeyEvent.KEYCODE_SEMICOLON) return true
        return false
    }

    private fun isModifierKey(keyCode: Int): Boolean {
        return keyCode == KeyEvent.KEYCODE_SHIFT_LEFT ||
                keyCode == KeyEvent.KEYCODE_SHIFT_RIGHT ||
                keyCode == KeyEvent.KEYCODE_CTRL_LEFT ||
                keyCode == KeyEvent.KEYCODE_CTRL_RIGHT ||
                keyCode == KeyEvent.KEYCODE_ALT_LEFT ||
                keyCode == KeyEvent.KEYCODE_ALT_RIGHT ||
                keyCode == KeyEvent.KEYCODE_CAPS_LOCK ||
                keyCode == KeyEvent.KEYCODE_NUM_LOCK ||
                keyCode == KeyEvent.KEYCODE_SCROLL_LOCK
    }

    private fun extractChar(event: KeyEvent): Char? {
        val keyCode = event.keyCode

        // Numpad mappings
        when (keyCode) {
            KeyEvent.KEYCODE_NUMPAD_0 -> return '0'
            KeyEvent.KEYCODE_NUMPAD_1 -> return '1'
            KeyEvent.KEYCODE_NUMPAD_2 -> return '2'
            KeyEvent.KEYCODE_NUMPAD_3 -> return '3'
            KeyEvent.KEYCODE_NUMPAD_4 -> return '4'
            KeyEvent.KEYCODE_NUMPAD_5 -> return '5'
            KeyEvent.KEYCODE_NUMPAD_6 -> return '6'
            KeyEvent.KEYCODE_NUMPAD_7 -> return '7'
            KeyEvent.KEYCODE_NUMPAD_8 -> return '8'
            KeyEvent.KEYCODE_NUMPAD_9 -> return '9'
            KeyEvent.KEYCODE_NUMPAD_DOT -> return '.'
            KeyEvent.KEYCODE_NUMPAD_DIVIDE -> return '/'
            KeyEvent.KEYCODE_NUMPAD_MULTIPLY -> return '*'
            KeyEvent.KEYCODE_NUMPAD_SUBTRACT -> return '-'
            KeyEvent.KEYCODE_NUMPAD_ADD -> return '+'
        }

        // Direct Unicode character from key character map (with meta/shift state applied)
        val u = event.keyCharacterMap?.get(keyCode, event.metaState) ?: event.unicodeChar
        if (u in 32..126) {
            return u.toChar()
        }

        // Fallback using event.unicodeChar directly
        val fallback = event.unicodeChar
        if (fallback in 32..126) {
            return fallback.toChar()
        }

        // Physical key code fallback for standard digits 0-9
        if (keyCode in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9) {
            return ('0'.code + (keyCode - KeyEvent.KEYCODE_0)).toChar()
        }

        // Physical key code fallback for standard letters A-Z
        if (keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) {
            return ('A'.code + (keyCode - KeyEvent.KEYCODE_A)).toChar()
        }

        // Common symbols
        val isShift = event.isShiftPressed
        when (keyCode) {
            KeyEvent.KEYCODE_MINUS -> return if (isShift) '_' else '-'
            KeyEvent.KEYCODE_EQUALS -> return if (isShift) '+' else '='
            KeyEvent.KEYCODE_SEMICOLON -> return if (isShift) ':' else ';'
            KeyEvent.KEYCODE_SLASH -> return if (isShift) '?' else '/'
            KeyEvent.KEYCODE_BACKSLASH -> return if (isShift) '|' else '\\'
            KeyEvent.KEYCODE_COMMA -> return if (isShift) '<' else ','
            KeyEvent.KEYCODE_PERIOD -> return if (isShift) '>' else '.'
            KeyEvent.KEYCODE_SPACE -> return ' '
        }

        return null
    }

    override fun onPause() {
        super.onPause()
        if (isVolumePressed) {
            isVolumePressed = false
            volumeChannel?.invokeMethod("onVolumeKeyUp", null)
        }
    }
}
