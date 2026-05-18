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
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket

class MainActivity : FlutterActivity() {
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

    // ─── LAN Discovery (NSD) ───
    private val TAG_LAN = "LessNetLAN"
    private val SERVICE_TYPE = "_lessnet._tcp"
    private var nsdManager: NsdManager? = null
    private var nsdRegistration: Any? = null // NsdManager.RegistrationListener
    private var nsdDiscovery: Any? = null // NsdManager.DiscoveryListener
    private var lanServerSocket: ServerSocket? = null
    private var lanServerThread: Thread? = null
    private var lanChannel: MethodChannel? = null
    private val LAN_PORT = 9876

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

        // LAN Discovery channel (NSD + TCP)
        lanChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lessnet.lan")
        lanChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "registerService" -> registerLanService(call, result)
                "unregisterService" -> unregisterLanService(result)
                "discoverServices" -> discoverLanServices(result)
                "stopDiscovery" -> stopLanDiscovery(result)
                "startTcpServer" -> startTcpServer(result)
                "stopTcpServer" -> stopTcpServer(result)
                "sendTcpMessage" -> sendTcpMessage(call, result)
                "getLocalIp" -> getLocalIp(result)
                else -> result.notImplemented()
            }
        }
        nsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
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

    // ─── LAN Discovery (NSD) Methods ───

    @SuppressLint("MissingPermission")
    private fun registerLanService(call: MethodCall, result: MethodChannel.Result) {
        try {
            val port = call.argument<Int>("port") ?: LAN_PORT
            val serviceName = call.argument<String>("serviceName") ?: "LessNet"

            val serviceInfo = NsdServiceInfo().apply {
                serviceName = serviceName
                serviceType = SERVICE_TYPE
                setPort(port)
            }

            val registrationListener = object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(info: NsdServiceInfo) {
                    Log.d(TAG_LAN, "Servicio NSD registrado: ${info.serviceName}")
                    runOnUiThread {
                        lanChannel?.invokeMethod("onServiceRegistered", info.serviceName)
                    }
                }
                override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                    Log.e(TAG_LAN, "Registro NSD fallido: errorCode=$errorCode")
                    runOnUiThread {
                        lanChannel?.invokeMethod("onRegistrationFailed", errorCode)
                    }
                }
                override fun onServiceUnregistered(info: NsdServiceInfo) {
                    Log.d(TAG_LAN, "Servicio NSD desregistrado: ${info.serviceName}")
                }
                override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                    Log.e(TAG_LAN, "Desregistro NSD fallido: errorCode=$errorCode")
                }
            }

            nsdRegistration = registrationListener
            nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG_LAN, "Error registrando servicio NSD: ${e.message}")
            result.error("NSD_ERROR", e.message, null)
        }
    }

    private fun unregisterLanService(result: MethodChannel.Result) {
        try {
            if (nsdRegistration != null) {
                @Suppress("UNCHECKED_CAST")
                nsdManager?.unregisterService(nsdRegistration as NsdManager.RegistrationListener)
                nsdRegistration = null
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("NSD_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun discoverLanServices(result: MethodChannel.Result) {
        try {
            val discoveryListener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) {
                    Log.d(TAG_LAN, "Descubrimiento NSD iniciado: $serviceType")
                }
                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    Log.d(TAG_LAN, "Servicio NSD encontrado: ${serviceInfo.serviceName}")
                    // Resolve the service to get host/port
                    nsdManager?.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                            Log.e(TAG_LAN, "Resolucion NSD fallida: ${serviceInfo.serviceName} errorCode=$errorCode")
                        }
                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            val host = serviceInfo.host?.hostAddress ?: ""
                            val port = serviceInfo.port
                            val name = serviceInfo.serviceName
                            Log.d(TAG_LAN, "Servicio NSD resuelto: $name @ $host:$port")
                            runOnUiThread {
                                val info = HashMap<String, Any>()
                                info["name"] = name
                                info["host"] = host
                                info["port"] = port
                                lanChannel?.invokeMethod("onServiceFound", info)
                            }
                        }
                    })
                }
                override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                    Log.d(TAG_LAN, "Servicio NSD perdido: ${serviceInfo.serviceName}")
                    runOnUiThread {
                        lanChannel?.invokeMethod("onServiceLost", serviceInfo.serviceName)
                    }
                }
                override fun onDiscoveryStopped(serviceType: String) {
                    Log.d(TAG_LAN, "Descubrimiento NSD detenido")
                }
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                    Log.e(TAG_LAN, "Inicio de descubrimiento fallido: errorCode=$errorCode")
                }
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                    Log.e(TAG_LAN, "Detencion de descubrimiento fallida: errorCode=$errorCode")
                }
            }

            nsdDiscovery = discoveryListener
            nsdManager?.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG_LAN, "Error descubriendo servicios NSD: ${e.message}")
            result.error("NSD_ERROR", e.message, null)
        }
    }

    private fun stopLanDiscovery(result: MethodChannel.Result) {
        try {
            if (nsdDiscovery != null) {
                @Suppress("UNCHECKED_CAST")
                nsdManager?.stopServiceDiscovery(nsdDiscovery as NsdManager.DiscoveryListener)
                nsdDiscovery = null
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("NSD_ERROR", e.message, null)
        }
    }

    private fun startTcpServer(result: MethodChannel.Result) {
        try {
            if (lanServerSocket != null) {
                result.success(true) // Already running
                return
            }
            lanServerThread = Thread {
                try {
                    lanServerSocket = ServerSocket(LAN_PORT)
                    Log.d(TAG_LAN, "Servidor TCP iniciado en puerto $LAN_PORT")
                    while (!Thread.currentThread().isInterrupted) {
                        try {
                            val client = lanServerSocket?.accept() ?: break
                            Log.d(TAG_LAN, "Cliente TCP conectado: ${client.inetAddress}")
                            // Read message from client
                            val reader = BufferedReader(InputStreamReader(client.getInputStream()))
                            val message = reader.readLine()
                            if (message != null) {
                                Log.d(TAG_LAN, "Mensaje TCP recibido: ${message.length} chars")
                                runOnUiThread {
                                    lanChannel?.invokeMethod("onTcpMessage", message)
                                }
                            }
                            client.close()
                        } catch (e: Exception) {
                            if (!Thread.currentThread().isInterrupted) {
                                Log.e(TAG_LAN, "Error aceptando conexion TCP: ${e.message}")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG_LAN, "Error servidor TCP: ${e.message}")
                }
            }
            lanServerThread?.start()
            result.success(true)
        } catch (e: Exception) {
            result.error("TCP_ERROR", e.message, null)
        }
    }

    private fun stopTcpServer(result: MethodChannel.Result) {
        try {
            lanServerThread?.interrupt()
            lanServerSocket?.close()
            lanServerSocket = null
            lanServerThread = null
            result.success(true)
        } catch (e: Exception) {
            result.error("TCP_ERROR", e.message, null)
        }
    }

    private fun sendTcpMessage(call: MethodCall, result: MethodChannel.Result) {
        try {
            val host = call.argument<String>("host") ?: ""
            val port = call.argument<Int>("port") ?: LAN_PORT
            val message = call.argument<String>("message") ?: ""

            if (host.isEmpty() || message.isEmpty()) {
                result.error("TCP_ERROR", "Host y mensaje requeridos", null)
                return
            }

            Thread {
                try {
                    val socket = Socket(host, port)
                    val writer = PrintWriter(socket.getOutputStream(), true)
                    writer.println(message)
                    writer.flush()
                    socket.close()
                    Log.d(TAG_LAN, "Mensaje TCP enviado a $host:$port (${message.length} chars)")
                    runOnUiThread {
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG_LAN, "Error enviando mensaje TCP: ${e.message}")
                    runOnUiThread {
                        result.error("TCP_ERROR", e.message, null)
                    }
                }
            }.start()
        } catch (e: Exception) {
            result.error("TCP_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun getLocalIp(result: MethodChannel.Result) {
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val wifiInfo = wifiManager.connectionInfo
            val ipInt = wifiInfo.ipAddress
            if (ipInt == 0) {
                result.success("")
                return
            }
            val ip = String.format("%d.%d.%d.%d",
                ipInt and 0xff,
                ipInt shr 8 and 0xff,
                ipInt shr 16 and 0xff,
                ipInt shr 24 and 0xff)
            result.success(ip)
        } catch (e: Exception) {
            result.error("IP_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        try {
            hotspotReservation?.close()
            hotspotReservation = null
        } catch (_: Exception) {}
        try {
            if (nsdDiscovery != null) {
                @Suppress("UNCHECKED_CAST")
                nsdManager?.stopServiceDiscovery(nsdDiscovery as NsdManager.DiscoveryListener)
            }
        } catch (_: Exception) {}
        try {
            if (nsdRegistration != null) {
                @Suppress("UNCHECKED_CAST")
                nsdManager?.unregisterService(nsdRegistration as NsdManager.RegistrationListener)
            }
        } catch (_: Exception) {}
        try {
            lanServerThread?.interrupt()
            lanServerSocket?.close()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
