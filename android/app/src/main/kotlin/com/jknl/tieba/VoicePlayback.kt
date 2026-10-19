package com.jknl.tieba

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VoicePlayback(private val context: Context) : MethodChannel.MethodCallHandler {
    private var player: MediaPlayer? = null
    private var identity = ""
    private var prepared = false
    private var failed = false
    private var pending: MethodChannel.Result? = null
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0 && prepared) player?.pause()
    }
    fun stop() {
        pending?.error("CANCELLED", "播放已停止", null)
        pending = null
        player?.release(); player = null; prepared = false; identity = ""
        @Suppress("DEPRECATION")
        audio.abandonAudioFocus(focusListener)
    }
    @Suppress("DEPRECATION")
    private fun start() {
        if (audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
            throw IllegalStateException("音频正在使用")
        player?.start()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: ""
        try {
            if (call.method != "play" && id != identity) {
                if (call.method == "state") result.success(mapOf("playing" to false, "position" to 0))
                else result.success(null)
                return
            }
            when (call.method) {
                "play" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (Uri.parse(url).scheme != "https") throw IllegalArgumentException()
                    stop(); identity = id; failed = false; pending = result
                    val next = MediaPlayer(); player = next
                    next.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    next.setOnPreparedListener {
                        if (player === next) {
                            try { prepared = true; start(); pending?.success(null); pending = null }
                            catch (_: Exception) { failed = true; pending?.error("PLAY_FAILED", "无法播放语音", null); pending = null }
                        }
                    }
                    next.setOnErrorListener { _, _, _ ->
                        if (player === next) { failed = true; prepared = false; pending?.error("PLAY_FAILED", "语音加载失败", null); pending = null }
                        true
                    }
                    next.setOnCompletionListener { @Suppress("DEPRECATION") audio.abandonAudioFocus(focusListener) }
                    next.setDataSource(context, Uri.parse(url), mapOf("Referer" to "https://tieba.baidu.com/"))
                    next.prepareAsync()
                }
                "pause" -> { if (prepared) player?.pause(); result.success(null) }
                "resume" -> { if (!prepared) throw IllegalStateException(); start(); result.success(null) }
                "stop" -> { stop(); result.success(null) }
                "state" -> result.success(mapOf("playing" to (prepared && player?.isPlaying == true), "position" to (if (prepared) player?.currentPosition else 0), "error" to failed))
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            if (pending === result) pending = null
            result.error("PLAY_FAILED", "语音播放失败", null)
        }
    }
}
