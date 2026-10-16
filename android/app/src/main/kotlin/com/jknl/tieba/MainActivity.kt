package com.jknl.tieba

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.app.Activity

class MainActivity : FlutterActivity() {
    private var pendingSave: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private var updateRunning = false

    private fun downloadUpdate(url: String, result: MethodChannel.Result) {
        val source = android.net.Uri.parse(url)
        if (source.scheme != "https" || source.host != "github.com" ||
            !source.path.orEmpty().startsWith("/HyePriest/tieba/releases/download/") ||
            !source.path.orEmpty().endsWith(".apk")) {
            result.error("INVALID_UPDATE", "更新地址无效", null); return
        }
        if (updateRunning) { result.error("BUSY", "正在下载更新", null); return }
        updateRunning = true
        Thread {
            val directory = java.io.File(cacheDir, "updates").apply { mkdirs() }
            val file = java.io.File(directory, "tieba-update.apk")
            val partial = java.io.File(directory, "tieba-update.partial.apk")
            try {
                var target = java.net.URL(url)
                var downloaded = false
                for (redirect in 0..6) {
                    if (target.protocol != "https" || target.host !in setOf(
                            "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")) {
                        throw java.io.IOException("更新地址跳转异常")
                    }
                    val connection = target.openConnection() as java.net.HttpURLConnection
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 15000
                    connection.readTimeout = 30000
                    connection.setRequestProperty("User-Agent", "Tieba-Android")
                    try {
                        val code = connection.responseCode
                        if (code in listOf(301, 302, 303, 307, 308)) {
                            val location = connection.getHeaderField("Location")
                                ?: throw java.io.IOException("无效跳转")
                            target = java.net.URL(target, location)
                            continue
                        }
                        if (code != 200) throw java.io.IOException("下载失败")
                        var size = 0L
                        connection.inputStream.use { input ->
                            partial.outputStream().use { output ->
                                val buffer = ByteArray(32768)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    size += count
                                    if (size > 100L * 1024 * 1024) throw java.io.IOException("安装包过大")
                                    output.write(buffer, 0, count)
                                }
                            }
                        }
                        val expected = connection.contentLengthLong
                        if (size == 0L || (expected > 0 && expected != size)) throw java.io.IOException("下载未完成")
                        downloaded = true
                        break
                    } finally { connection.disconnect() }
                }
                if (!downloaded) throw java.io.IOException("下载跳转过多")
                val info = packageManager.getPackageArchiveInfo(partial.absolutePath, 0)
                    ?: throw java.io.IOException("安装包无效")
                val installed = packageManager.getPackageInfo(packageName, 0)
                val version = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                val current = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                if (info.packageName != packageName || version <= current) throw java.io.IOException("安装包版本不匹配")
                file.delete()
                if (!partial.renameTo(file)) throw java.io.IOException("无法保存安装包")
                runOnUiThread {
                    updateRunning = false
                    // Download completion never opens a window over the reader.
                    result.success("ready")
                }
            } catch (_: Exception) {
                partial.delete()
                runOnUiThread {
                    updateRunning = false
                    result.error("DOWNLOAD_FAILED", "更新下载未完成，请重试", null)
                }
            }
        }.start()
    }

    private fun installUpdate(result: MethodChannel.Result) {
        val file = java.io.File(cacheDir, "updates/tieba-update.apk")
        if (!file.isFile || updateRunning) {
            result.error("MISSING_UPDATE", "请先下载更新", null); return
        }
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            try {
                startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    android.net.Uri.parse("package:$packageName")))
                result.success("permission")
            } catch (_: Exception) { result.error("PERMISSION", "无法打开安装权限设置", null) }
            return
        }
        try {
            val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.updates", file)
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            result.success("installer")
        } catch (_: Exception) { result.error("INSTALL_FAILED", "无法打开安装程序", null) }
    }

    private fun saveImage(bytes: ByteArray, name: String, mime: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 29) {
            Thread {
                var uri: android.net.Uri? = null
                try {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, name)
                        put(MediaStore.Images.Media.MIME_TYPE, mime)
                        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Tieba")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw java.io.IOException("无法创建图片文件")
                    val stream = contentResolver.openOutputStream(uri) ?: throw java.io.IOException("无法打开图片文件")
                    stream.use { it.write(bytes) }
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    runOnUiThread { result.success(true) }
                } catch (e: Exception) {
                    uri?.let { try { contentResolver.delete(it, null, null) } catch (_: Exception) {} }
                    runOnUiThread { result.error("SAVE_FAILED", "无法保存图片，请检查存储空间", null) }
                }
            }.start()
        } else {
            if (pendingSave != null) { result.error("BUSY", "正在保存图片", null); return }
            pendingSave = result
            pendingBytes = bytes
            try {
                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_TITLE, name)
                }, 7301)
            } catch (_: Exception) {
                pendingSave = null; pendingBytes = null
                result.error("SAVE_FAILED", "无法打开文件保存窗口", null)
            }
        }
    }

    @Deprecated("Legacy document picker callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7301) return
        val result = pendingSave ?: return
        val bytes = pendingBytes
        pendingSave = null; pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) { result.success(false); return }
        Thread {
            try {
                val stream = contentResolver.openOutputStream(uri) ?: throw java.io.IOException("无法打开文件")
                stream.use { it.write(bytes) }
                runOnUiThread { result.success(true) }
            } catch (_: Exception) {
                runOnUiThread { result.error("SAVE_FAILED", "图片写入失败", null) }
            }
        }.start()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jknl.tieba/session")
            .setMethodCallHandler { call, result ->
                val manager = CookieManager.getInstance()
                when (call.method) {
                    "downloadUpdate" -> downloadUpdate(call.argument<String>("url") ?: "", result)
                    "installUpdate" -> installUpdate(result)
                    "shareText" -> {
                        val text = call.argument<String>("text")
                        val title = call.argument<String>("title") ?: "贴吧"
                        if (text.isNullOrBlank() || text.length > 10000) {
                            result.error("INVALID_SHARE", "分享内容为空或过长", null)
                        } else {
                            try {
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(Intent.EXTRA_SUBJECT, title)
                                    putExtra(Intent.EXTRA_TEXT, text)
                                }
                                startActivity(Intent.createChooser(send, "分享"))
                                result.success(null)
                            } catch (_: Exception) {
                                result.error("SHARE_FAILED", "无法打开系统分享窗口", null)
                            }
                        }
                    }
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val mime = call.argument<String>("mime")
                        val name = call.argument<String>("name")
                        if (bytes == null || bytes.isEmpty() || bytes.size > 32 * 1024 * 1024 ||
                            mime !in setOf("image/jpeg", "image/png", "image/gif", "image/webp") ||
                            name == null || !name.matches(Regex("tieba_[0-9]+\\.(jpg|png|gif|webp)"))) {
                            result.error("INVALID_IMAGE", "图片格式不正确", null)
                        } else saveImage(bytes, name, mime!!, result)
                    }
                    "getBaiduCookies" -> {
                        val allowed = setOf("BDUSS", "STOKEN", "BAIDUID", "BDUSS_BFESS", "STOKEN_BFESS", "BAIDUID_BFESS")
                        val cookies = mutableMapOf<String, String>()
                        for (url in listOf("https://www.baidu.com/", "https://passport.baidu.com/", "https://wappass.baidu.com/", "https://tieba.baidu.com/")) {
                            manager.getCookie(url)?.split(";")?.forEach { item ->
                                val pair = item.trim().split("=", limit = 2)
                                if (pair.size == 2 && pair[0] in allowed) cookies[pair[0]] = pair[1]
                            }
                        }
                        result.success(cookies)
                    }
                    "clearBaiduCookies" -> manager.removeAllCookies { manager.flush(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
}
