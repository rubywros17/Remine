package com.remine.remine

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 관심사 알림 채널(8.0+는 채널이 있어야 알림이 뜬다). 이미 있으면 그대로 둔다. 서버는 이 id로 보낸다.
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("interest_alerts", "관심사 알림", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 알림을 영구 거부한 사용자를 이 앱의 알림 설정 화면으로 보낸다(lib/data/remote/push.dart), 설치 시각.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "remine/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        )
                        result.success(null)
                    }
                    // 자기 캡처 1회 정리의 시작점(lib/data/device/own_capture.dart). 밀리초.
                    "firstInstallTime" ->
                        result.success(packageManager.getPackageInfo(packageName, 0).firstInstallTime)
                    // 갤러리 휴지통(MediaStore.createTrashRequest)은 Android 11+에만 있다(lib/data/device/photo_manager_gallery_reader.dart).
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    // 첫 분석 화면 동안 화면 꺼짐 방지(lib/screens/sync_gate.dart). 창 플래그라 권한이 필요 없고 앱이 앞에 있을 때만 효과가 있다.
                    "keepScreenOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    // 예전 스크린샷 정리 조건(lib/data/remote/sync_service.dart). Wi-Fi는 ACCESS_NETWORK_STATE(일반 권한, 묻지 않음).
                    "isWifi" -> result.success(isOnWifi())
                    // 디버그 로그용: 지금 네트워크의 전송 방식 목록(예: "active=WIFI,VPN · wifi=true").
                    "networkInfo" -> result.success(networkInfo())
                    // 충전 중인지. 권한이 필요 없다.
                    "isCharging" ->
                        result.success(getSystemService(BatteryManager::class.java)?.isCharging == true)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 데이터가 Wi-Fi로 나가는지. 기본 네트워크(activeNetwork)가 Wi-Fi면 true.
     * VPN이 켜져 있으면 기본 네트워크는 VPN이라 TRANSPORT_WIFI가 없을 수 있다 → 그때는 인터넷이 되는 기반 네트워크 중
     * Wi-Fi가 있는지 본다. 모바일 데이터뿐이면 false.
     */
    private fun isOnWifi(): Boolean {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return false
        val active = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        if (active.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return true
        if (!active.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return false
        @Suppress("DEPRECATION") // 기반 네트워크를 고르는 다른 공개 API가 없다(API 31의 콜백 방식은 비동기)
        return cm.allNetworks.any { n ->
            val c = cm.getNetworkCapabilities(n)
            c != null &&
                c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        }
    }

    private fun networkInfo(): String {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return "no ConnectivityManager"
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "active=none · wifi=false"
        val names = mapOf(
            NetworkCapabilities.TRANSPORT_WIFI to "WIFI",
            NetworkCapabilities.TRANSPORT_CELLULAR to "CELLULAR",
            NetworkCapabilities.TRANSPORT_VPN to "VPN",
            NetworkCapabilities.TRANSPORT_ETHERNET to "ETHERNET",
            NetworkCapabilities.TRANSPORT_BLUETOOTH to "BLUETOOTH",
        )
        val transports = names.filterKeys { caps.hasTransport(it) }.values.joinToString(",")
        return "active=${transports.ifEmpty { "?" }} · wifi=${isOnWifi()}"
    }
}
