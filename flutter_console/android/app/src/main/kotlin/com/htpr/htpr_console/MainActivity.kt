package com.htpr.htpr_console

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var gnss: GnssBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // GNSS 数据流
        val bridge = GnssBridge(applicationContext)
        gnss = bridge
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, GNSS_CHANNEL)
            .setStreamHandler(bridge)

        // 工具通道：日志目录 / 写文件
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UTIL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLogDir" -> {
                        // 外部私有目录：/sdcard/Android/data/<pkg>/files
                        // 可用 USB / adb pull 直接取出，无需权限
                        val d = getExternalFilesDir(null) ?: filesDir
                        val logs = File(d, "logs")
                        if (!logs.exists()) logs.mkdirs()
                        result.success(logs.absolutePath)
                    }
                    "writeFile" -> {
                        val name = call.argument<String>("name") ?: "log.txt"
                        val content = call.argument<String>("content") ?: ""
                        val dir = call.argument<String>("dir")
                            ?: (getExternalFilesDir(null) ?: filesDir).absolutePath
                        try {
                            val f = File(dir, name)
                            f.parentFile?.mkdirs()
                            f.writeText(content, Charsets.UTF_8)
                            result.success(f.absolutePath)
                        } catch (e: Exception) {
                            result.error("WRITE_FAIL", e.message, null)
                        }
                    }
                    "listLogs" -> {
                        val d = getExternalFilesDir(null) ?: filesDir
                        val logs = File(d, "logs")
                        val arr = ArrayList<String>()
                        logs.listFiles()?.sortedByDescending { it.lastModified() }
                            ?.forEach { arr.add("${it.name}|${it.length()}") }
                        result.success(arr)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val GNSS_CHANNEL = "htpr/gnss/stream"
        private const val UTIL_CHANNEL = "htpr/util"
    }
}
