package com.remine.remine

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 알림을 영구 거부한 사용자를 이 앱의 알림 설정 화면으로 보낸다(lib/data/remote/push.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "remine/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openNotificationSettings") {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
