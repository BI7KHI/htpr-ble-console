package com.htpr.htpr_console

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt

/**
 * 原生 GNSS 桥
 *  - 位置：经纬度 / 海拔 / 速度 / 方位 / 精度
 *  - 星空图：每颗卫星的 方位角(az) / 仰角(el) / 载噪比(cn0) / 星座 / 是否参与定位
 * 通过 EventChannel 以 JSON 流推给 Dart。
 */
class GnssBridge(private val ctx: Context) : EventChannel.StreamHandler {

    private var sink: EventChannel.EventSink? = null
    private var lm: LocationManager? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var listener: LocationListener? = null

    private var sats = JSONArray()
    private var satCount = 0
    private var usedCount = 0
    private var lastEmit = 0L

    companion object {
        private const val CONST_UNKNOWN = 0
        private const val CONST_GPS = 1
        private const val CONST_SBAS = 2
        private const val CONST_GLONASS = 3
        private const val CONST_QZSS = 4
        private const val CONST_BEIDOU = 5
        private const val CONST_GALILEO = 6
        private const val CONST_IRNSS = 7

        fun constName(t: Int): String = when (t) {
            CONST_GPS -> "GPS"
            CONST_SBAS -> "SBAS"
            CONST_GLONASS -> "GLO"
            CONST_QZSS -> "QZSS"
            CONST_BEIDOU -> "BDS"
            CONST_GALILEO -> "GAL"
            CONST_IRNSS -> "IRNSS"
            else -> "?"
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        start()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    private fun hasPerm(): Boolean =
        ContextCompat.checkSelfPermission(
            ctx, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    private fun send(o: JSONObject) {
        val s = sink ?: return
        Handler(Looper.getMainLooper()).post { s.success(o.toString()) }
    }

    private fun sendError(msg: String) {
        val o = JSONObject()
        o.put("error", msg)
        send(o)
    }

    private fun start() {
        if (!hasPerm()) {
            sendError("缺少定位权限")
            return
        }
        val manager = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        lm = manager

        val lis = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                val o = JSONObject()
                o.put("lat", location.latitude)
                o.put("lon", location.longitude)
                o.put("alt", if (location.hasAltitude()) location.altitude else JSONObject.NULL)
                o.put("speed", if (location.hasSpeed()) location.speed.toDouble() else 0.0)
                o.put("bearing", if (location.hasBearing()) location.bearing.toDouble() else JSONObject.NULL)
                o.put("acc", if (location.hasAccuracy()) location.accuracy.toDouble() else JSONObject.NULL)
                o.put("provider", location.provider ?: "gps")
                o.put("time", location.time)
                runCatching { o.put("vAcc", if (location.hasVerticalAccuracy()) location.verticalAccuracyMeters.toDouble() else JSONObject.NULL) }
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    runCatching { o.put("bearingAcc", if (location.hasBearingAccuracy()) location.bearingAccuracyDegrees.toDouble() else JSONObject.NULL) }
                    runCatching { o.put("speedAcc", if (location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond.toDouble() else JSONObject.NULL) }
                }
                o.put("sats", sats)
                o.put("count", satCount)
                o.put("usedCount", usedCount)
                send(o)
            }

            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                sendError("GPS 已关闭，请在系统设置中打开定位")
            }

            @Deprecated("legacy")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        listener = lis
        try {
            manager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 500L, 0f, lis, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            sendError("无法启用 GPS: ${e.message}")
        }

        val cb = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                val arr = JSONArray()
                var used = 0
                for (i in 0 until status.satelliteCount) {
                    val o = JSONObject()
                    o.put("svid", status.getSvid(i))
                    o.put("const", constName(status.getConstellationType(i)))
                    o.put("az", status.getAzimuthDegrees(i).toDouble())
                    o.put("el", status.getElevationDegrees(i).toDouble())
                    o.put("cn0", status.getCn0DbHz(i).toDouble())
                    val u = status.usedInFix(i)
                    o.put("used", u)
                    if (u) used++
                    arr.put(o)
                }
                sats = arr
                satCount = status.satelliteCount
                usedCount = used

                val now = System.currentTimeMillis()
                if (now - lastEmit > 900) {
                    lastEmit = now
                    val o = JSONObject()
                    o.put("sats", sats)
                    o.put("count", satCount)
                    o.put("usedCount", usedCount)
                    o.put("satsOnly", true)
                    send(o)
                }
            }
        }
        gnssCallback = cb
        try {
            manager.registerGnssStatusCallback(cb, Handler(Looper.getMainLooper()))
        } catch (_: Exception) {
        }

        // 立即回一次空包，让 UI 知道已启动
        val o = JSONObject()
        o.put("sats", sats)
        o.put("count", 0)
        o.put("usedCount", 0)
        send(o)
    }

    private fun stop() {
        val manager = lm ?: return
        listener?.let { runCatching { manager.removeUpdates(it) } }
        gnssCallback?.let { runCatching { manager.unregisterGnssStatusCallback(it) } }
        listener = null
        gnssCallback = null
        lm = null
    }
}
