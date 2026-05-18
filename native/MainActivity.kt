package PACKAGE_PLACEHOLDER

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.location.Location
import android.location.LocationManager
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // BLE Peripheral channel
        val bleChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lessnet.ble_peripheral")
        val plugin = BlePeripheralPlugin(this)
        plugin.setChannel(bleChannel)

        // Hotspot channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lessnet.hotspot").setMethodCallHandler { call, result ->
            when (call.method) {
                "startHotspot" -> startHotspot(call, result)
                "stopHotspot" -> stopHotspot(result)
                "connectToWifi" -> connectToWifi(call, result)
                "isHotspotSupported" -> result.success(isHotspotSupported())
                else -> result.notImplemented()
            }
        }

        // Location channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lessnet.location").setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocation" -> getLocation(result)
                "hasLocationPermission" -> result.success(hasLocationPermission())
                "requestLocationPermission" -> requestLocationPermission(result)
                else -> result.notImplemented()
            }
        }

        // Flashlight channel (used by SOS overlay) — turnOn / turnOff / isAvailable
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lessnet.flashlight").setMethodCallHandler { call, result ->
            when (call.method) {
                "turnOn" -> turnFlashlight(true, result)
                "turnOff" -> turnFlashlight(false, result)
                "isAvailable" -> result.success(isFlashlightAvailable())
                else -> result.notImplemented()
            }
        }

        // Torch channel (used by Morse code page) — on / off / hasTorch
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lessnet.torch").setMethodCallHandler { call, result ->
            when (call.method) {
                "on" -> turnFlashlight(true, result)
                "off" -> turnFlashlight(false, result)
                "hasTorch" -> result.success(isFlashlightAvailable())
                else -> result.notImplemented()
            }
        }
    }

    // ─── Hotspot Methods ───

    private fun isHotspotSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
    }

    @SuppressLint("MissingPermission")
    private fun startHotspot(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // Check NEARBY_WIFI_DEVICES permission on Android 13+
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    if (checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED) {
                        result.error("PERMISSION", "Se requiere permiso NEARBY_WIFI_DEVICES para iniciar el hotspot. Concedelo en la configuracion de la app.", null)
                        return
                    }
                }

                val ssid = call.argument<String>("ssid") ?: "LessNet"
                val password = call.argument<String>("password") ?: "lessnet123"

                val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                manager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                        hotspotReservation = reservation
                        result.success(true)
                    }
                    override fun onFailed(reason: Int) {
                        result.error("HOTSPOT_ERROR", "Failed to start hotspot: reason=$reason", null)
                    }
                    override fun onStopped() {
                        hotspotReservation = null
                    }
                }, null)
            } catch (e: Exception) {
                result.error("HOTSPOT_ERROR", e.message, null)
            }
        } else {
            try {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val config = WifiConfiguration()
                config.SSID = "\"${call.argument<String>("ssid") ?: "LessNet"}\""
                config.preSharedKey = "\"${call.argument<String>("password") ?: "lessnet123"}\""
                config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                val netId = wifiManager.addNetwork(config)
                wifiManager.disconnect()
                wifiManager.enableNetwork(netId, true)
                wifiManager.reconnect()
                result.success(true)
            } catch (e: Exception) {
                result.error("HOTSPOT_ERROR", "Hotspot no soportado en Android < 8: ${e.message}", null)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopHotspot(result: MethodChannel.Result) {
        try {
            hotspotReservation?.close()
            hotspotReservation = null
            result.success(true)
        } catch (e: Exception) {
            result.error("HOTSPOT_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectToWifi(call: MethodCall, result: MethodChannel.Result) {
        try {
            val ssid = call.argument<String>("ssid") ?: "LessNet"
            val password = call.argument<String>("password") ?: "lessnet123"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ cannot programmatically connect to WiFi
                // Open WiFi settings instead
                val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                result.success(true)
            } else {
                @Suppress("DEPRECATION")
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val config = WifiConfiguration()
                config.SSID = "\"$ssid\""
                config.preSharedKey = "\"$password\""
                config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                val netId = wifiManager.addNetwork(config)
                wifiManager.disconnect()
                wifiManager.enableNetwork(netId, true)
                wifiManager.reconnect()
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("WIFI_ERROR", e.message, null)
        }
    }

    // ─── Location Methods ───

    private fun hasLocationPermission(): Boolean {
        return androidx.core.content.ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            androidx.core.app.ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), 1001)
            result.success(true)
        } else {
            result.success(true)
        }
    }

    @SuppressLint("MissingPermission")
    private fun getLocation(result: MethodChannel.Result) {
        try {
            if (!hasLocationPermission()) {
                result.error("PERMISSION", "Location permission not granted", null)
                return
            }

            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            var bestLocation: Location? = null

            val providers = locationManager.getProviders(true)
            for (provider in providers) {
                val location = locationManager.getLastKnownLocation(provider)
                if (location != null) {
                    if (bestLocation == null || location.accuracy < bestLocation.accuracy) {
                        bestLocation = location
                    }
                }
            }

            if (bestLocation != null) {
                val locationMap = HashMap<String, Any>()
                locationMap["latitude"] = bestLocation.latitude
                locationMap["longitude"] = bestLocation.longitude
                locationMap["accuracy"] = bestLocation.accuracy
                locationMap["altitude"] = bestLocation.altitude
                result.success(locationMap)
            } else {
                result.error("LOCATION_ERROR", "No location available", null)
            }
        } catch (e: Exception) {
            result.error("LOCATION_ERROR", e.message, null)
        }
    }

    // ─── Flashlight / Torch Methods ───

    private fun isFlashlightAvailable(): Boolean {
        val pm = packageManager
        return pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_FLASH)
    }

    private fun turnFlashlight(on: Boolean, result: MethodChannel.Result) {
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
            if (cameraId != null) {
                cameraManager.setTorchMode(cameraId, on)
                result.success(true)
            } else {
                result.error("FLASHLIGHT_ERROR", "No flashlight available", null)
            }
        } catch (e: Exception) {
            result.error("FLASHLIGHT_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        try {
            hotspotReservation?.close()
            hotspotReservation = null
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
