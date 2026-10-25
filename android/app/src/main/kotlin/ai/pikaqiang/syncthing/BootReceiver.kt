package ai.pikaqiang.syncthing

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机 / 应用更新后自动启动（用户在设置页开启「开机自启」后生效）。
 * Flutter shared_preferences 写入的键带 "flutter." 前缀，存储于
 * "FlutterSharedPreferences" 中。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE
                )
                if (prefs.getBoolean("flutter.startOnBoot", false)) {
                    SyncthingService.start(context)
                }
            }
        }
    }
}
