package com.remine.remine

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                    else -> result.notImplemented()
                }
            }
    }
}
