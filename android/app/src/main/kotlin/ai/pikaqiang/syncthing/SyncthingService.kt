package ai.pikaqiang.syncthing

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * 托管 syncthing 进程的前台服务。
 *
 * - 进程从 nativeLibraryDir 中的 libsyncthing.so 启动（见 SyncthingConfig）
 * - stdout/stderr 合并后逐行转发到 SyncthingBus（→ Flutter 日志页）
 * - StatusPoller 每 3 秒拉取 REST（速率/各文件夹同步进度）刷新前台通知：
 *     标题=Syncthing 运行中；正文=↑/↓ 速率；展开=逐文件夹同步进度行
 * - 进程退出后服务自动停止；停止动作为 destroy()（SIGTERM，syncthing 优雅落盘）
 *   被 Android 清理（force-stop 等）时进程组整体被 SIGKILL，syncthing 不会残留。
 */
class SyncthingService : Service() {

    companion object {
        const val ACTION_START = "ai.pikaqiang.syncthing.action.START"
        const val ACTION_STOP = "ai.pikaqiang.syncthing.action.STOP"
        private const val CHANNEL_ID = "syncthing_service"
        private const val NOTIF_ID = 1
        private const val POLL_INTERVAL_MS = 3000L
        private const val FOLDERS_REFRESH_EVERY = 10 // 每 N 次轮询刷新一次文件夹列表

        val processRef = AtomicReference<Process?>(null)

        fun start(context: Context) {
            val intent = Intent(context, SyncthingService::class.java).setAction(ACTION_START)
            context.startForegroundService(intent)
        }
    }

    private var process: Process? = null
    private var lastInfo: SyncthingConfig.Info? = null
    private val pollerRunning = AtomicBoolean(false)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSyncthing()
                return START_NOT_STICKY
            }
        }
        startForegroundWithType()
        if (process == null || process?.isAlive != true) {
            startSyncthing()
        }
        return START_STICKY
    }

    private fun startForegroundWithType() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.notif_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        val notification = buildNotification(null, emptyList(), 0, -1)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun contentIntents(): Pair<PendingIntent, PendingIntent> {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, SyncthingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return open to stop
    }

    /**
     * 构建通知。折叠态：速率 +（同步中摘要 或 全部已同步）；
     * 展开态：InboxStyle 逐文件夹行（同步中/扫描中在前，已同步在后，上限 6 行）；
     * 同步中时附带系统进度条。
     */
    private fun buildNotification(
        rates: String?,
        activeLines: List<String>,
        idleCount: Int,
        progress: Int,
    ): Notification {
        val (open, stop) = contentIntents()
        val ratesText = rates ?: getString(R.string.notif_running_text)

        // 折叠态正文：速率常驻；有活动文件夹时附第一条摘要，否则「全部已同步」
        val collapsed = buildString {
            append(ratesText)
            if (activeLines.isNotEmpty()) {
                append("  ·  ")
                append(activeLines.first())
                if (activeLines.size > 1) append(" 等 ${activeLines.size} 项")
            } else if (idleCount > 0) {
                append("  ·  全部已同步")
            }
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setContentTitle(getString(R.string.notif_running_title))
            .setContentText(collapsed)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, getString(R.string.notif_action_stop), stop)

        if (progress in 0..100) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(0, 0, false) // 清除历史进度
        }

        // 展开态：活动行 + 已同步计数行
        val style = NotificationCompat.InboxStyle(builder)
        for (line in activeLines.take(6)) style.addLine(line)
        if (idleCount > 0) {
            style.addLine(
                if (activeLines.isEmpty()) "全部已同步（$idleCount 个文件夹）"
                else "其余 $idleCount 个文件夹已同步"
            )
        }
        builder.setStyle(style)
        return builder.build()
    }

    // ------------------------------------------------------------------
    // 状态轮询 → 通知刷新
    // ------------------------------------------------------------------

    private fun apiGet(path: String): JSONObject? {
        val info = lastInfo ?: return null
        return try {
            val conn = URL("http://127.0.0.1:${info.apiPort}$path").openConnection() as HttpURLConnection
            conn.connectTimeout = 2000
            conn.readTimeout = 3000
            conn.setRequestProperty("X-API-Key", info.apiKey)
            try {
                if (conn.responseCode != 200) return null
                conn.inputStream.bufferedReader().use { it.readText() }.let { JSONObject(it) }
            } finally {
                conn.disconnect()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun apiGetArray(path: String): org.json.JSONArray? {
        val info = lastInfo ?: return null
        return try {
            val conn = URL("http://127.0.0.1:${info.apiPort}$path").openConnection() as HttpURLConnection
            conn.connectTimeout = 2000
            conn.readTimeout = 3000
            conn.setRequestProperty("X-API-Key", info.apiKey)
            try {
                if (conn.responseCode != 200) return null
                conn.inputStream.bufferedReader().use { it.readText() }
                    .let { org.json.JSONArray(it) }
            } finally {
                conn.disconnect()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun fmtBytes(v0: Long): String {
        var v = v0.toDouble()
        val units = arrayOf("B", "KiB", "MiB", "GiB", "TiB")
        var i = 0
        while (v >= 1024 && i < units.size - 1) {
            v /= 1024; i++
        }
        return if (i == 0) "${v.toLong()} ${units[i]}" else String.format("%.1f %s", v, units[i])
    }

    private fun fmtRate(bytesPerSec: Double): String {
        var v = bytesPerSec
        val units = arrayOf("B/s", "KiB/s", "MiB/s", "GiB/s")
        var i = 0
        while (v >= 1024 && i < units.size - 1) {
            v /= 1024; i++
        }
        return if (i == 0) "${v.toInt()} ${units[i]}" else String.format("%.1f %s", v, units[i])
    }

    private fun startStatusPoller() {
        if (!pollerRunning.compareAndSet(false, true)) return
        Thread({
            var foldersCache: List<Pair<String, String>>? = null // id to label
            var tick = 0
            // 速率差分基准（v2 API 无 *BytesPerSec 字段）
            var prevRatesIn = -1L
            var prevRatesOut = -1L
            var prevRatesAt = 0L
            var lastRatesText: String? = null
            val nm = getSystemService(NotificationManager::class.java)
            while (pollerRunning.get() && process?.isAlive == true) {
                try {
                    tick++
                    // 速率：v2 API 只有累计字节（1.25 起移除 *BytesPerSec），
                    // 用 (本次累计-上次累计)/间隔 差分计算，与官方 Web 前端做法一致。
                    val ratesText: String?
                    val conn = apiGet("/rest/system/connections")
                    val total = conn?.optJSONObject("total")
                    val nowMs = android.os.SystemClock.elapsedRealtime()
                    if (total != null) {
                        val inT = total.optLong("inBytesTotal", 0)
                        val outT = total.optLong("outBytesTotal", 0)
                        if (prevRatesAt > 0 && nowMs - prevRatesAt >= 500) {
                            val dt = (nowMs - prevRatesAt) / 1000.0
                            val up = ((outT - prevRatesOut) / dt).coerceAtLeast(0.0)
                            val down = ((inT - prevRatesIn) / dt).coerceAtLeast(0.0)
                            lastRatesText = "↑ ${fmtRate(up)}   ↓ ${fmtRate(down)}"
                            prevRatesIn = inT
                            prevRatesOut = outT
                            prevRatesAt = nowMs
                        } else if (prevRatesAt <= 0) {
                            // 首次采样只建基准
                            prevRatesIn = inT
                            prevRatesOut = outT
                            prevRatesAt = nowMs
                        }
                        ratesText = lastRatesText
                    } else {
                        ratesText = lastRatesText
                    }

                    // 文件夹列表（低频刷新）
                    if (foldersCache == null || tick % FOLDERS_REFRESH_EVERY == 0) {
                        // 拉取失败保留 null 下一轮重试，避免把「未就绪时的空列表」缓存住
                        val cfg = apiGetArray("/rest/config/folders")
                        if (cfg != null) {
                            val list = mutableListOf<Pair<String, String>>()
                            for (i in 0 until cfg.length()) {
                                val f = cfg.optJSONObject(i) ?: continue
                                if (f.optBoolean("paused", false)) continue
                                list.add(f.optString("id") to f.optString("label").ifEmpty { f.optString("id") })
                            }
                            foldersCache = list
                        }
                    }

                    // 各文件夹状态：活动行（同步/扫描/错误）+ 已同步计数
                    val activeLines = mutableListOf<String>()
                    var idleCount = 0
                    var firstProgress = -1
                    for ((id, label) in foldersCache.orEmpty()) {
                        val st = apiGet("/rest/db/status?folder=$id") ?: continue
                        val state = st.optString("state", "")
                        when (state) {
                            "syncing" -> {
                                val global = st.optLong("globalBytes", 0)
                                val need = st.optLong("needBytes", 0)
                                val pct = if (global > 0) {
                                    ((global - need) * 100 / global).toInt().coerceIn(0, 100)
                                } else 100
                                val line = buildString {
                                    append(label).append("  同步中 ").append(pct).append('%')
                                    if (need > 0) append("  ·  差 ").append(fmtBytes(need))
                                }
                                activeLines.add(line)
                                if (firstProgress < 0) firstProgress = pct
                            }
                            "sync-preparing" -> activeLines.add("$label  准备同步")
                            "scanning" -> {
                                val pct = if (st.has("scanPercentage")) st.optDouble("scanPercentage", -1.0) else -1.0
                                activeLines.add(
                                    if (pct >= 0) "$label  扫描中 ${pct.toInt()}%"
                                    else "$label  扫描中"
                                )
                            }
                            "cleaning" -> activeLines.add("$label  清理版本")
                            "error" -> activeLines.add("$label  错误: ${st.optString("error", "").take(40)}")
                            else -> idleCount++
                        }
                    }
                    nm.notify(
                        NOTIF_ID,
                        buildNotification(ratesText, activeLines, idleCount, firstProgress)
                    )
                } catch (_: Exception) {
                }
                Thread.sleep(POLL_INTERVAL_MS)
            }
            pollerRunning.set(false)
        }, "syncthing-status").start()
    }

    // ------------------------------------------------------------------
    // 进程生命周期
    // ------------------------------------------------------------------

    private fun startSyncthing() {
        SyncthingBus.postState(SyncthingBus.STATE_STARTING)
        try {
            val info = SyncthingConfig.ensureConfig(this)
            lastInfo = info
            val pb = ProcessBuilder(
                info.binaryPath,
                "serve",
                "--home", info.homeDir,
                "--log-file", File(File(info.homeDir).parentFile, "syncthing.log").absolutePath,
            )
            pb.environment()["STNORESTART"] = "1"
            pb.environment()["STNOUPGRADE"] = "1"
            pb.environment()["HOME"] = info.homeDir
            pb.redirectErrorStream(true)
            val proc = pb.start()
            process = proc
            processRef.set(proc)

            Thread({
                try {
                    BufferedReader(proc.inputStream.reader()).useLines { lines ->
                        for (line in lines) SyncthingBus.postLog(line)
                    }
                } catch (_: Exception) {
                }
            }, "syncthing-log").start()

            Thread({
                try {
                    proc.waitFor()
                } catch (_: InterruptedException) {
                }
                val code = proc.exitValue()
                pollerRunning.set(false)
                processRef.compareAndSet(proc, null)
                if (process === proc) process = null
                if (SyncthingBus.currentState != SyncthingBus.STATE_STOPPED) {
                    if (code == 0) {
                        SyncthingBus.postState(SyncthingBus.STATE_STOPPED)
                    } else {
                        SyncthingBus.postState(
                            SyncthingBus.STATE_ERROR,
                            "syncthing 进程退出 (code=$code)",
                        )
                    }
                }
                stopSelf()
            }, "syncthing-wait").start()

            SyncthingBus.postState(SyncthingBus.STATE_RUNNING)
            startStatusPoller()
        } catch (e: Exception) {
            SyncthingBus.postState(SyncthingBus.STATE_ERROR, e.message ?: e.toString())
            stopSelf()
        }
    }

    private fun stopSyncthing() {
        SyncthingBus.postState(SyncthingBus.STATE_STOPPED)
        pollerRunning.set(false)
        try {
            process?.let { p ->
                p.destroy() // SIGTERM，syncthing 优雅关闭并落盘
                Thread {
                    try {
                        if (!p.waitFor(10, TimeUnit.SECONDS)) p.destroyForcibly()
                    } catch (_: InterruptedException) {
                    }
                }.start()
            }
        } finally {
            stopSelf()
        }
    }

    /**
     * 用户划掉任务时前台服务继续运行（同步本来就要后台常驻）。
     * Android 真正清理（force-stop / 内存回收）会按进程组 SIGKILL，
     * syncthing 子进程同组，不会残留（onDestroy 兜底再 destroy 一次）。
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        pollerRunning.set(false)
        process?.destroy()
        process = null
        processRef.set(null)
        if (SyncthingBus.currentState == SyncthingBus.STATE_RUNNING ||
            SyncthingBus.currentState == SyncthingBus.STATE_STARTING
        ) {
            SyncthingBus.postState(SyncthingBus.STATE_STOPPED)
        }
        super.onDestroy()
    }
}
