package com.remine.remine

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
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
                    else -> result.notImplemented()
                }
            }
    }
}
