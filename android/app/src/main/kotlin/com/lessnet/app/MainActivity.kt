package com.lessnet.app

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TORCH_CHANNEL = "com.lessnet.torch"
    private var cameraManager: CameraManager? = null
    private var cameraId: String? = null

    override fun onResume() {
        super.onResume()
        setupTorch()
    }

    private fun setupTorch() {
        try {
            cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            for (id in cameraManager!!.cameraIdList) {
                val characteristics = cameraManager!!.getCameraCharacteristics(id)
                val hasFlash = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
                if (hasFlash) {
                    cameraId = id
                    break
                }
            }
        } catch (e: Exception) {
            // No camera/torch available
        }
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TORCH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "on" -> {
                        try {
                            if (cameraId != null && cameraManager != null) {
                                cameraManager!!.setTorchMode(cameraId!!, true)
                                result.success(true)
                            } else {
                                result.error("NO_TORCH", "Este dispositivo no tiene linterna", null)
                            }
                        } catch (e: Exception) {
                            result.error("TORCH_ERROR", e.message, null)
                        }
                    }
                    "off" -> {
                        try {
                            if (cameraId != null && cameraManager != null) {
                                cameraManager!!.setTorchMode(cameraId!!, false)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("TORCH_ERROR", e.message, null)
                        }
                    }
                    "hasTorch" -> {
                        result.success(cameraId != null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
