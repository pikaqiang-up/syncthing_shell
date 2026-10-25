package ai.pikaqiang.syncthing

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArrayList

/**
 * 进程内事件总线：SyncthingService → Flutter（EventChannel）与状态缓存。
 *
 * 消息为 Map，格式：
 *   {type: "state", state: "stopped"|"starting"|"running"|"error", message?: String}
 *   {type: "log",   line: String}
 */
object SyncthingBus {
    const val STATE_STOPPED = "stopped"
    const val STATE_STARTING = "starting"
    const val STATE_RUNNING = "running"
    const val STATE_ERROR = "error"

    @Volatile
    var currentState: String = STATE_STOPPED
        private set

    @Volatile
    var lastError: String? = null
        private set

    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()

    fun addListener(l: (Map<String, Any?>) -> Unit) {
        listeners.add(l)
        // 立即回放当前状态，避免订阅时序问题
        l(mapOf("type" to "state", "state" to currentState, "message" to lastError))
    }

    fun removeListener(l: (Map<String, Any?>) -> Unit) {
        listeners.remove(l)
    }

    fun postState(state: String, message: String? = null) {
        currentState = state
        if (state == STATE_ERROR) lastError = message else lastError = null
        emit(mapOf("type" to "state", "state" to state, "message" to message))
    }

    fun postLog(line: String) {
        emit(mapOf("type" to "log", "line" to line))
    }

    private fun emit(msg: Map<String, Any?>) {
        mainHandler.post {
            for (l in listeners) l(msg)
        }
    }
}
