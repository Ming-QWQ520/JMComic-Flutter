package com.ming.jmcomic

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

/**
 * 桌面小组件原生 API 客户端（对齐 Flutter 端 JmClient 的 JM 协议）。
 *
 * 让小组件的「刷新」在桌面端直接拉取随机推荐，无需打开 APP：
 * - 签名：token = MD5("{ts}18comicAPP")，tokenparam = "{ts},2.1.7"；
 * - 响应：JSON {code,msg,data}；data 为 Base64 字符串时按
 *   AES-256-ECB/PKCS5 解密（密钥 = MD5("{ts}185Hcomic3PAPP7R") 的
 *   32 字节 hex ASCII），明文 data 直接当 JSON 数组用；
 * - 服务器时间校准：用响应 Date 头校正设备时钟偏差（偏差过大时
 *   服务端会 400 拒签），校准后对同一线路重试一次。
 */
internal object JmWidgetApi {

    private val API_HOSTS = listOf(
        "https://www.cdnhjk.net",
        "https://www.cdngwc.cc",
        "https://www.cdngwc.net",
        "https://www.cdngwc.club",
    )

    /// 图片（封面）线路，下载失败时依次尝试
    val IMG_HOSTS = listOf(
        "https://cdn-msp.jmapiproxy1.cc",
        "https://cdn-msp.jmapinodeudzn.net",
        "https://cdn-msp.jmapiproxy3.cc",
        "https://cdn-msp.jmdanjonproxy.xyz",
    )

    private const val TOKEN_SECRET = "18comicAPP"
    private const val DATA_SECRET = "185Hcomic3PAPP7R"
    private const val HEADER_VER = "2.1.7"
    private const val CLIENT_VERSION = "v1.3.6"
    private const val UA =
        "Mozilla/5.0 (Linux; Android 7.1.2; DT1901A Build/N2G47O; wv) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 " +
            "Chrome/86.0.4240.198 Mobile Safari/537.36"

    /// 服务器时钟偏差（秒），由任意响应的 Date 头校正
    @Volatile
    private var clockOffsetSec: Long = 0

    private fun md5Hex(s: String): String {
        val d = MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
        return d.joinToString("") { "%02x".format(it) }
    }

    /// AES-256-ECB/PKCS5 + Base64 解密（密钥 = 32 字节 hex ASCII）
    private fun decryptData(b64: String, ts: String): String? = try {
        val key = md5Hex(ts + DATA_SECRET).toByteArray(Charsets.US_ASCII)
        val cipher = Cipher.getInstance("AES/ECB/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"))
        String(
            cipher.doFinal(android.util.Base64.decode(b64, android.util.Base64.DEFAULT)),
            Charsets.UTF_8
        )
    } catch (_: Exception) {
        null
    }

    private fun syncClock(dateHeader: String?) {
        if (dateHeader.isNullOrEmpty()) return
        try {
            val fmt = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("GMT")
            val server: Date = fmt.parse(dateHeader) ?: return
            clockOffsetSec = (server.time - System.currentTimeMillis()) / 1000
        } catch (_: Exception) {
        }
    }

    /// 拉取随机推荐，返回 [{name,id}, ...]（最多 [limit] 条）；失败返回 null。
    fun fetchRandomAlbums(limit: Int = 6): JSONArray? {
        for (host in API_HOSTS) {
            for (attempt in 0..1) {
                val ts = (System.currentTimeMillis() / 1000 + clockOffsetSec).toString()
                val conn: HttpURLConnection = try {
                    (URL("$host/random_recommend/?lang=CN").openConnection() as HttpURLConnection)
                        .apply {
                            connectTimeout = 6000
                            readTimeout = 12000
                            setRequestProperty("tokenparam", "$ts,$HEADER_VER")
                            setRequestProperty("token", md5Hex(ts + TOKEN_SECRET))
                            setRequestProperty("version", CLIENT_VERSION)
                            setRequestProperty("User-Agent", UA)
                        }
                } catch (_: Exception) {
                    break
                }
                try {
                    val httpCode = conn.responseCode
                    syncClock(conn.getHeaderField("Date"))
                    if (httpCode != 200) continue
                    val body = readAll(conn.inputStream)
                    val envelope = JSONObject(body)
                    val code = envelope.optInt("code", 0)
                    if (code == 200) {
                        val albums = parseAlbums(envelope.opt("data"), ts, limit)
                        if (albums.length() > 0) return albums
                        return null
                    }
                    // 400/403 可能是时钟偏差被拒签：校准后对同线路重试一次
                    if ((code == 400 || code == 403) && attempt == 0) continue
                    return null
                } catch (_: Exception) {
                    break // 网络异常，换下一线路
                } finally {
                    conn.disconnect()
                }
            }
        }
        return null
    }

    /// 从 data（明文 JSON 数组 / AES 密文字符串）解析出 {name,id} 列表
    private fun parseAlbums(data: Any?, ts: String, limit: Int): JSONArray {
        val arr: JSONArray = when (data) {
            is JSONArray -> data
            is String -> {
                val plain = decryptData(data, ts) ?: return JSONArray()
                try {
                    JSONArray(plain)
                } catch (_: Exception) {
                    JSONArray()
                }
            }
            else -> return JSONArray()
        }
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optString("id", "")
            if (id.isEmpty()) continue
            out.put(
                JSONObject()
                    .put("name", o.optString("name", ""))
                    .put("id", id)
            )
            if (out.length() >= limit) break
        }
        return out
    }

    private fun readAll(stream: InputStream): String {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(8192)
        var n: Int
        while (stream.read(buf).also { n = it } > 0) out.write(buf, 0, n)
        stream.close()
        return out.toString("UTF-8")
    }

    // ------------------------------------------------------------------
    // 封面下载（磁盘缓存 + 多线路 + 重试）。
    //
    // widget 进程短命（每次更新都是新进程），内存缓存形同虚设——此前
    // 每次渲染都要重新下载，网络稍有中断（SocketException / Incomplete
    // image data）就显示不出封面。现在封面按 albumId 落盘到 cacheDir，
    // 命中磁盘直接用，彻底解决"经常无法显示封面"。
    // ------------------------------------------------------------------

    private const val COVER_DIR = "widget_covers"

    private fun coverFile(context: Context, albumId: String): File {
        val dir = File(context.cacheDir, COVER_DIR)
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "cover_$albumId.jpg")
    }

    /// 只读磁盘缓存的封面（不触发网络）；未命中返回 null。
    fun peekCoverBitmap(context: Context, albumId: String): Bitmap? {
        val f = coverFile(context, albumId)
        if (!f.exists()) return null
        return BitmapFactory.decodeFile(f.absolutePath)
    }

    /// 取封面 Bitmap：磁盘缓存优先，未命中走网络（多线路 × 2 次重试），
    /// 成功后落盘。失败返回 null。
    fun fetchCoverBitmap(context: Context, albumId: String, coverUrl: String): Bitmap? {
        val f = coverFile(context, albumId)
        if (f.exists()) {
            val cached = BitmapFactory.decodeFile(f.absolutePath)
            if (cached != null) return cached
            f.delete() // 坏缓存清理
        }
        val urls = if (coverUrl.isNotEmpty()) {
            listOf(coverUrl)
        } else {
            IMG_HOSTS.map { host ->
                val h = if (host.endsWith('/')) host.dropLast(1) else host
                "$h/media/albums/${albumId}_3x4.jpg"
            }
        }
        for (u in urls) {
            for (attempt in 0..1) {
                var conn: HttpURLConnection? = null
                try {
                    conn = (URL(u).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 6000
                        readTimeout = 12000
                        setRequestProperty("User-Agent", UA)
                        setRequestProperty("Accept", "image/*,*/*;q=0.8")
                    }
                    val raw = conn.inputStream.readBytes()
                    if (raw.size < 64) continue // 截断响应（Incomplete image data）
                    val bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size)
                    if (bmp != null) {
                        val scaled = scaleBitmap(bmp, 86 * 2)
                        try {
                            f.outputStream().use { out ->
                                scaled.compress(
                                    Bitmap.CompressFormat.JPEG, 85, out
                                )
                            }
                        } catch (_: Exception) {
                        }
                        return scaled
                    }
                } catch (_: Exception) {
                    // 网络中断：同 URL 重试一次，再不行换下一线路
                } finally {
                    conn?.disconnect()
                }
            }
        }
        return null
    }

    private fun scaleBitmap(src: Bitmap, target: Int): Bitmap {
        val w = src.width
        val h = src.height
        val ratio = if (w >= h) target.toFloat() / w else target.toFloat() / h
        if (ratio >= 1f) return src
        val nw = (w * ratio).toInt().coerceAtLeast(1)
        val nh = (h * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, nw, nh, true)
    }
}
