package com.globalagencies.godown_scanner

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private val LINES_REGEX = Regex("[\r\n]+")
        private val CTRL_CHARS_REGEX = Regex("[\\x00-\\x1F\\x7F-\\x9F]")
    }

    private val VOLUME_CHANNEL = "com.globalagencies.godown_scanner/volume_key"
    private val SCANNER_CHANNEL = "com.globalagencies.godown_scanner/scanner"

    private val imm by lazy {
        getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
    }

    private var volumeChannel: MethodChannel? = null
    private var scannerChannel: MethodChannel? = null

    private var isInterceptingVolume = false
    private var isVolumePressed = false

    private var isScannerEnabled = true
    private val scannerBuffer = StringBuilder()
    private var lastKeystrokeTime: Long = 0L
    private var lastBurstEndTime: Long = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var burstRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ensure Android soft keyboard never steals focus or pops up when a physical scanner is connected
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
    }

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
                    val onlyIfStale = call.argument<Boolean>("onlyIfStale") ?: false
                    val now = System.currentTimeMillis()
                    if (!onlyIfStale || lastKeystrokeTime == 0L || (now - lastKeystrokeTime) > 500L) {
                        clearScannerBuffer()
                    }
                    currentFocus?.let { view ->
                        imm?.hideSoftInputFromWindow(view.windowToken, 0)
                    }
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
        lastBurstEndTime = System.currentTimeMillis()

        val raw = scannerBuffer.toString()
        scannerBuffer.setLength(0)

        if (raw.isBlank()) return

        val lines = raw.split(LINES_REGEX)
        for (line in lines) {
            val clean = line.replace(CTRL_CHARS_REGEX, "").trim().uppercase()
            if (clean.length >= 2) {
                scannerChannel?.invokeMethod("onBarcodeScanned", clean)
            }
        }
    }

    private fun scheduleBurstCompletion(delayMs: Long) {
        burstRunnable?.let { mainHandler.removeCallbacks(it) }
        burstRunnable = Runnable { finalizeScannerBurst() }
        mainHandler.postDelayed(burstRunnable!!, delayMs)
    }

    private fun determineQuietWindow(): Long {
        // Cold-start Bluetooth / 2.4GHz wake-up adaptive safety window:
        // When a scanner wakes from idle/sleep (> 5s), the first 1-3 characters are followed by a
        // longer radio link negotiation gap (up to 1200ms) before subsequent characters stream in.
        // Using a 1500ms safety window guarantees cold bursts are NEVER cut off early!
        val cold = lastBurstEndTime == 0L || (System.currentTimeMillis() - lastBurstEndTime > 5000L)
        return when {
            scannerBuffer.length < 4 -> if (cold) 1500L else 650L
            else -> 350L
        }
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
            if (isPotentialScannerKey(event)) {
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
                if (scannerBuffer.isEmpty()) {
                    currentFocus?.let { view ->
                        imm?.hideSoftInputFromWindow(view.windowToken, 0)
                    }
                }
                lastKeystrokeTime = now
                scannerBuffer.append(characters)
                scheduleBurstCompletion(determineQuietWindow())
                return true
            }
        }

        if (event.action != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        val now = System.currentTimeMillis()
        if (lastKeystrokeTime != 0L && now - lastKeystrokeTime > 1500) {
            scannerBuffer.setLength(0)
        }

        // Ensure soft keyboard doesn't compose characters on start of hardware scan burst
        if (scannerBuffer.isEmpty() && isPotentialScannerKey(event)) {
            currentFocus?.let { view ->
                imm?.hideSoftInputFromWindow(view.windowToken, 0)
            }
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

        // Handle multi-character payload attached directly to ACTION_DOWN
        val directChars = event.characters
        if (!directChars.isNullOrEmpty() && directChars.length > 1) {
            lastKeystrokeTime = now
            scannerBuffer.append(directChars)
            val endsWithTerm = directChars.endsWith('\n') || directChars.endsWith('\r')
            scheduleBurstCompletion(if (endsWithTerm) 25 else determineQuietWindow())
            return true
        }

        // Check for Terminator Keys (Enter / Numpad Enter / \n / \r)
        val isTerminator = (keyCode == KeyEvent.KEYCODE_ENTER ||
                keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER ||
                event.unicodeChar == '\n'.code ||
                event.unicodeChar == '\r'.code)

        if (isTerminator) {
            lastKeystrokeTime = now
            scannerBuffer.append('\n')
            // Fast 25ms finalization on Enter - immediate response!
            scheduleBurstCompletion(25)
            return true
        }

        // Extract character
        val char = extractChar(event)
        if (char != null) {
            lastKeystrokeTime = now
            scannerBuffer.append(char)
            // Use cold-start adaptive safety window (650ms for first few characters, 350ms once rolling)
            scheduleBurstCompletion(determineQuietWindow())
            return true
        }

        // If it's a potential scanner key that couldn't be mapped to printable ASCII,
        // still swallow it so raw unprintable characters never leak into UI fields during a burst!
        if (isPotentialScannerKey(event)) {
            return true
        }

        return super.dispatchKeyEvent(event)
    }

    private fun isPotentialScannerKey(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (keyCode == KeyEvent.KEYCODE_ENTER || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER || keyCode == KeyEvent.KEYCODE_TAB) return true
        if (keyCode in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9) return true
        if (keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) return true
        if (keyCode in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9) return true
        if (isModifierKey(keyCode)) return true
        if (event.isPrintingKey || event.unicodeChar >= 32 || !event.characters.isNullOrEmpty()) return true
        if (keyCode == KeyEvent.KEYCODE_MINUS || keyCode == KeyEvent.KEYCODE_SLASH ||
            keyCode == KeyEvent.KEYCODE_PERIOD || keyCode == KeyEvent.KEYCODE_SPACE ||
            keyCode == KeyEvent.KEYCODE_EQUALS || keyCode == KeyEvent.KEYCODE_SEMICOLON ||
            keyCode == KeyEvent.KEYCODE_COMMA || keyCode == KeyEvent.KEYCODE_BACKSLASH ||
            keyCode == KeyEvent.KEYCODE_GRAVE || keyCode == KeyEvent.KEYCODE_LEFT_BRACKET ||
            keyCode == KeyEvent.KEYCODE_RIGHT_BRACKET || keyCode == KeyEvent.KEYCODE_APOSTROPHE ||
            keyCode == KeyEvent.KEYCODE_STAR || keyCode == KeyEvent.KEYCODE_POUND ||
            keyCode == KeyEvent.KEYCODE_AT || keyCode == KeyEvent.KEYCODE_PLUS) return true
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
        val chars = event.characters
        if (!chars.isNullOrEmpty()) {
            return chars[0]
        }

        val keyCode = event.keyCode

        // 1. Numpad mappings (very common on 2.4G wireless scanners & OTG wedges)
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
            KeyEvent.KEYCODE_NUMPAD_EQUALS -> return '='
        }

        // 2. Direct Unicode with event's metaState (Shift, Alt, etc.)
        val uWithMeta = event.getUnicodeChar(event.metaState)
        if (uWithMeta in 32..126) {
            return uWithMeta.toChar()
        }

        // 3. Direct Unicode without metaState
        val uNoMeta = event.getUnicodeChar(0)
        if (uNoMeta in 32..126) {
            return uNoMeta.toChar()
        }

        // 4. KeyCharacterMap explicit lookup (with safety against primitive 0)
        val kcm = event.keyCharacterMap
        if (kcm != null) {
            val k1 = kcm.get(keyCode, event.metaState)
            if (k1 in 32..126) return k1.toChar()
            val k0 = kcm.get(keyCode, 0)
            if (k0 in 32..126) return k0.toChar()
        }

        // 5. Physical key code fallback for standard top-row digits 0-9
        if (keyCode in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9) {
            return ('0'.code + (keyCode - KeyEvent.KEYCODE_0)).toChar()
        }

        // 6. Physical key code fallback for standard letters A-Z
        val isShift = event.isShiftPressed || (event.metaState and KeyEvent.META_SHIFT_ON != 0)
        if (keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) {
            val baseChar = ('A'.code + (keyCode - KeyEvent.KEYCODE_A)).toChar()
            return if (isShift) baseChar else baseChar.lowercaseChar()
        }

        // 7. Comprehensive symbol mappings
        when (keyCode) {
            KeyEvent.KEYCODE_MINUS -> return if (isShift) '_' else '-'
            KeyEvent.KEYCODE_EQUALS -> return if (isShift) '+' else '='
            KeyEvent.KEYCODE_SEMICOLON -> return if (isShift) ':' else ';'
            KeyEvent.KEYCODE_SLASH -> return if (isShift) '?' else '/'
            KeyEvent.KEYCODE_BACKSLASH -> return if (isShift) '|' else '\\'
            KeyEvent.KEYCODE_COMMA -> return if (isShift) '<' else ','
            KeyEvent.KEYCODE_PERIOD -> return if (isShift) '>' else '.'
            KeyEvent.KEYCODE_SPACE -> return ' '
            KeyEvent.KEYCODE_GRAVE -> return if (isShift) '~' else '`'
            KeyEvent.KEYCODE_LEFT_BRACKET -> return if (isShift) '{' else '['
            KeyEvent.KEYCODE_RIGHT_BRACKET -> return if (isShift) '}' else ']'
            KeyEvent.KEYCODE_APOSTROPHE -> return if (isShift) '"' else '\''
            KeyEvent.KEYCODE_STAR -> return '*'
            KeyEvent.KEYCODE_POUND -> return '#'
            KeyEvent.KEYCODE_AT -> return '@'
            KeyEvent.KEYCODE_PLUS -> return '+'
            KeyEvent.KEYCODE_TAB -> return '\t'
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
