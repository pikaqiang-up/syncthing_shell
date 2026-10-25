package ai.pikaqiang.syncthing

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "app.syncthing/native"
        private const val EVENTS = "app.syncthing/events"
        private const val REQ_PICK_DIR = 41
        private const val REQ_NOTIF = 42
        private const val REQ_ALL_FILES = 43
        private const val REQ_BATTERY = 44
    }

    private var dirPickResult: MethodChannel.Result? = null
    private var notifResult: MethodChannel.Result? = null
    private var allFilesResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13+ 通知权限（前台服务通知需要）
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF
            )
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_PICK_DIR -> {
                val pending = dirPickResult
                dirPickResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    pending?.success(null)
                    return
                }
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                } catch (_: SecurityException) {
                }
                pending?.success(treeUriToPath(uri))
            }

            REQ_ALL_FILES -> {
                allFilesResult?.success(Environment.isExternalStorageManager())
                allFilesResult = null
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF && notifResult != null) {
            notifResult?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            )
            notifResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getServiceInfo" -> threadToResult(result) {
                        val info = SyncthingConfig.ensureConfig(this)
                        mapOf(
                            "binaryPath" to info.binaryPath,
                            "homeDir" to info.homeDir,
                            "apiPort" to info.apiPort,
                            "apiKey" to info.apiKey,
                            "guiAddress" to info.guiAddress,
                            "state" to SyncthingBus.currentState,
                            "lastError" to SyncthingBus.lastError,
                        )
                    }

                    "start" -> {
                        SyncthingService.start(this)
                        result.success(true)
                    }

                    "stop" -> {
                        startService(
                            Intent(this, SyncthingService::class.java)
                                .setAction(SyncthingService.ACTION_STOP)
                        )
                        result.success(true)
                    }

                    "state" -> result.success(SyncthingBus.currentState)
                    "lastError" -> result.success(SyncthingBus.lastError)

                    "pickDirectory" -> {
                        dirPickResult = result
                        startActivityForResult(
                            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQ_PICK_DIR
                        )
                    }

                    "requestNotificationPermission" -> {
                        notifResult = result
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                REQ_NOTIF,
                            )
                        } else {
                            notifResult?.success(true)
                            notifResult = null
                        }
                    }

                    "isAllFilesAccessGranted" ->
                        result.success(Environment.isExternalStorageManager())

                    "requestAllFilesAccess" -> {
                        allFilesResult = result
                        startActivityForResult(
                            Intent(
                                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                            REQ_ALL_FILES,
                        )
                    }

                    "isIgnoringBatteryOptimizations" ->
                        result.success(
                            (getSystemService(Context.POWER_SERVICE) as PowerManager)
                                .isIgnoringBatteryOptimizations(packageName)
                        )

                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            startActivityForResult(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName"),
                                ),
                                REQ_BATTERY,
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            Toast.makeText(this, "无法打开电池设置: ${e.message}", Toast.LENGTH_LONG)
                                .show()
                            result.success(false)
                        }
                    }

                    "openWebUi" -> {
                        val url = call.argument<String>("url")
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var listener: ((Map<String, Any?>) -> Unit)? = null

                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    val l: (Map<String, Any?>) -> Unit = { events.success(it) }
                    listener = l
                    SyncthingBus.addListener(l)
                }

                override fun onCancel(args: Any?) {
                    listener?.let { SyncthingBus.removeListener(it) }
                    listener = null
                }
            }
        )
    }

    private fun threadToResult(result: MethodChannel.Result, body: () -> Any?) {
        Thread {
            try {
                val value = body()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { result.error("native_error", e.message, null) }
            }
        }.start()
    }

    /**
     * 把 SAF 返回的 tree URI 尽力转换为真实文件系统路径。
     * 仅支持主外部存储（primary volume）；其余情况返回 null，由 UI 引导手动输入。
     */
    private fun treeUriToPath(uri: Uri): String? {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(uri) // e.g. "primary:Download/backup"
            if (docId.startsWith("primary:")) {
                val rest = docId.removePrefix("primary:").removePrefix("/")
                File(Environment.getExternalStorageDirectory(), rest).absolutePath
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }
}
