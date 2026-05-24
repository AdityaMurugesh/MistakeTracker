package com.example.mistake_tracker

import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private var pendingResult: MethodChannel.Result? = null
	private val CHANNEL = "mistake_tracker/notifications"
	private val REQ_CODE = 1001

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"requestNotificationPermission" -> {
					// On Android 13+ request POST_NOTIFICATIONS runtime permission
					if (Build.VERSION.SDK_INT >= 33) {
						val has = ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
						if (has) {
							result.success(true)
						} else {
							// store result and request permission
							pendingResult = result
							ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQ_CODE)
						}
					} else {
						// Older Android versions don't need runtime permission for notifications
						result.success(true)
					}
				}
				"checkNotificationPermission" -> {
					// Check current permission state without prompting
					if (Build.VERSION.SDK_INT >= 33) {
						val has = ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
						result.success(has)
					} else {
						result.success(true)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode == REQ_CODE) {
			val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
			pendingResult?.success(granted)
			pendingResult = null
		}
	}
}
