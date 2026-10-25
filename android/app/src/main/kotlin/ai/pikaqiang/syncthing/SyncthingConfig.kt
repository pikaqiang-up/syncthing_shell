package ai.pikaqiang.syncthing

import android.content.Context
import java.io.File
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

/**
 * Syncthing 配置引导：首次启动运行 `syncthing generate` 生成 config.xml 与证书，
 * 之后解析（必要时注入）GUI 监听地址和 API key，供 REST 客户端使用。
 *
 * 注意：本文件是「壳」与 Syncthing 之间的唯一配置约定，升级 Syncthing 时
 * 只需确认 `generate` 子命令与 config.xml 中 gui 节点字段未变。
 */
object SyncthingConfig {

    data class Info(
        val binaryPath: String,
        val homeDir: String,
        val apiPort: Int,
        val apiKey: String,
        val guiAddress: String,
    )

    fun homeDir(context: Context): File = File(context.filesDir, "syncthing-home")

    fun binaryPath(context: Context): String =
        File(context.applicationInfo.nativeLibraryDir, "libsyncthing.so").absolutePath

    /**
     * 确保配置存在。首次调用会运行一次 `syncthing generate`（约 1–3 秒），
     * 必须在后台线程执行。
     */
    @Synchronized
    fun ensureConfig(context: Context): Info {
        val home = homeDir(context)
        home.mkdirs()
        val bin = binaryPath(context)
        if (!File(bin).exists()) {
            throw IllegalStateException("找不到内嵌的 syncthing 二进制: $bin")
        }
        if (!File(home, "config.xml").exists()) {
            runBinary(bin, home, listOf("generate", "--home", home.absolutePath, "--no-port-probing"))
        }
        return readInfo(bin, home)
    }

    private fun runBinary(bin: String, home: File, args: List<String>) {
        val pb = ProcessBuilder(listOf(bin) + args)
        pb.environment()["STNORESTART"] = "1"
        pb.environment()["STNOUPGRADE"] = "1"
        val proc = pb.start()
        val output = proc.inputStream.bufferedReader().readText()
        val ok = proc.waitFor(60, TimeUnit.SECONDS)
        if (!ok || proc.exitValue() != 0) {
            throw IllegalStateException("syncthing ${args.first()} 失败 (exit=${proc.exitValue()}):\n$output")
        }
    }

    /** 从 config.xml 读取 gui 信息；缺失的 apikey/地址会写回文件。 */
    fun readInfo(bin: String, home: File): Info {
        val configFile = File(home, "config.xml")
        var xml = configFile.readText()

        val apiKey = Regex("<apikey>([^<]+)</apikey>").find(xml)?.groupValues?.get(1)
            ?: run {
                val key = randomApiKey()
                xml = xml.replace(
                    Regex("(<gui[^>]*>)"),
                    "$1\n            <apikey>$key</apikey>",
                )
                configFile.writeText(xml)
                key
            }

        var address = Regex("<address>([^<]+)</address>").find(xml)?.groupValues?.get(1)
        if (address == null || address.contains(":0")) {
            address = "127.0.0.1:8384"
            xml = xml.replaceFirst(
                Regex("(<gui[^>]*>)"),
                "$1\n            <address>$address</address>",
            )
            configFile.writeText(xml)
        }

        val port = address.substringAfterLast(':').toIntOrNull() ?: 8384
        return Info(
            binaryPath = bin,
            homeDir = home.absolutePath,
            apiPort = port,
            apiKey = apiKey,
            guiAddress = address,
        )
    }

    private fun randomApiKey(): String {
        val chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        val rnd = SecureRandom()
        return buildString { repeat(32) { append(chars[rnd.nextInt(chars.length)]) } }
    }
}
