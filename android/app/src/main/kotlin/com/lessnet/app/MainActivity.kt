package com.lessnet.app

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
import android.os.Looper
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
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.content.BroadcastReceiver
import android.content.IntentFilter

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

    // ─── Wi-Fi Direct ───
    private val TAG_P2P = "LessNetP2P"
    private var p2pManager: WifiP2pManager? = null
    private var p2pChannel: WifiP2pManager.Channel? = null
    private var p2pReceiver: BroadcastReceiver? = null
    private var p2pGroupOwner: Boolean = false
    private var p2pConnected: Boolean = false
    private var p2pGroupOwnerAddress: String = ""
    private var wifiDirectChannel: MethodChannel? = null
    private var p2pServerSocket: ServerSocket? = null
    private var p2pServerThread: Thread? = null
    private val P2P_PORT = 9877

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

        // Wi-Fi Direct channel
        wifiDirectChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lessnet.wifi_direct")
        wifiDirectChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> initializeWifiP2p(result)
                "discoverPeers" -> discoverP2pPeers(result)
                "stopDiscovery" -> stopP2pDiscovery(result)
                "connect" -> connectP2pPeer(call, result)
                "disconnect" -> disconnectP2p(result)
                "isConnected" -> result.success(p2pConnected)
                "isGroupOwner" -> result.success(p2pGroupOwner)
                "getGroupOwnerAddress" -> result.success(p2pGroupOwnerAddress)
                "startP2pServer" -> startP2pServer(result)
                "stopP2pServer" -> stopP2pServer(result)
                "sendP2pMessage" -> sendP2pMessage(call, result)
                else -> result.notImplemented()
            }
        }
        initializeWifiP2pSilent()
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
                        result.error("PERMISSION", "Se requiere permiso NEARBY_WIFI_DEVICES para iniciar el hotspot.", null)
                        return
                    }
                }

                val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                manager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                        hotspotReservation = reservation
                        // Extract actual SSID and password from the hotspot configuration
                        val wifiConfig = reservation?.wifiConfiguration
                        val hotspotInfo = HashMap<String, Any>()
                        hotspotInfo["success"] = true
                        if (wifiConfig != null) {
                            hotspotInfo["ssid"] = wifiConfig.SSID?.removeSurrounding("\"") ?: "LessNet"
                            hotspotInfo["password"] = wifiConfig.preSharedKey?.removeSurrounding("\"") ?: ""
                            @Suppress("DEPRECATION")
                            hotspotInfo["securityType"] = wifiConfig.allowedKeyManagement.toString()
                            Log.d("LessNet", "Hotspot iniciado - SSID: ${wifiConfig.SSID}, seguridad: ${wifiConfig.allowedKeyManagement}")
                        } else {
                            // On Android 13+ wifiConfiguration may be null
                            hotspotInfo["ssid"] = "LessNet-Local"
                            hotspotInfo["password"] = ""
                            hotspotInfo["note"] = "LocalOnlyHotspot: Android genera SSID/password aleatorios. Verifica en Ajustes > Hotspot."
                            Log.d("LessNet", "Hotspot iniciado (config null en Android 13+)")
                        }
                        // Notify Dart with hotspot info
                        runOnUiThread {
                            val hotspotChannel = MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger!!, "com.lessnet.hotspot")
                            hotspotChannel.invokeMethod("onHotspotStarted", hotspotInfo)
                        }
                        result.success(hotspotInfo)
                    }
                    override fun onFailed(reason: Int) {
                        val reasonStr = when (reason) {
                            WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL -> "NO_CHANNEL"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_GENERIC -> "GENERIC"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE -> "INCOMPATIBLE_MODE"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED -> "TETHERING_DISALLOWED"
                            else -> "UNKNOWN($reason)"
                        }
                        Log.e("LessNet", "Hotspot fallido: reason=$reasonStr")
                        result.error("HOTSPOT_ERROR", "Failed to start hotspot: $reasonStr", null)
                    }
                    override fun onStopped() {
                        hotspotReservation = null
                        Log.d("LessNet", "Hotspot detenido")
                        runOnUiThread {
                            try {
                                val hotspotChannel = MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger!!, "com.lessnet.hotspot")
                                hotspotChannel.invokeMethod("onHotspotStopped", true)
                            } catch (_: Exception) {}
                        }
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
                @Suppress("DEPRECATION")
                val netId = wifiManager.addNetwork(config)
                wifiManager.disconnect()
                wifiManager.enableNetwork(netId, true)
                wifiManager.reconnect()
                val hotspotInfo = HashMap<String, Any>()
                hotspotInfo["success"] = true
                hotspotInfo["ssid"] = call.argument<String>("ssid") ?: "LessNet"
                hotspotInfo["password"] = call.argument<String>("password") ?: "lessnet123"
                result.success(hotspotInfo)
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
                Log.d("LessNet", "Linterna ${if (on) "ENCENDIDA" else "APAGADA"}")
                result.success(true)
            } else {
                result.error("FLASHLIGHT_ERROR", "No flashlight available", null)
            }
        } catch (e: SecurityException) {
            // Camera in use by another app
            Log.e("LessNet", "Linterna: cámara en uso por otra app: ${e.message}")
            result.error("FLASHLIGHT_ERROR", "Cámara en uso por otra aplicación", null)
        } catch (e: Exception) {
            Log.e("LessNet", "Linterna error: ${e.message}")
            result.error("FLASHLIGHT_ERROR", e.message, null)
        }
    }

    // ─── LAN Discovery (NSD) Methods ───

    @SuppressLint("MissingPermission")
    private fun registerLanService(call: MethodCall, result: MethodChannel.Result) {
        try {
            val port = call.argument<Int>("port") ?: LAN_PORT
            val localServiceName = call.argument<String>("serviceName") ?: "LessNet"

            val serviceInfo = NsdServiceInfo().apply {
                serviceName = localServiceName
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

    // ─── Wi-Fi Direct Methods ───

    private fun initializeWifiP2pSilent() {
        try {
            p2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
            p2pChannel = p2pManager?.initialize(this, Looper.getMainLooper(), null)

            // Register BroadcastReceiver for P2P events
            val intentFilter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            }

            p2pReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.action) {
                        WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                            val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                            val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                            Log.d(TAG_P2P, "Wi-Fi Direct state: ${if (enabled) "ENABLED" else "DISABLED"}")
                            runOnUiThread {
                                wifiDirectChannel?.invokeMethod("onP2pStateChanged", enabled)
                            }
                        }
                        WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                            p2pManager?.requestPeers(p2pChannel) { peerList: WifiP2pDeviceList ->
                                val peers = ArrayList<HashMap<String, String>>()
                                for (device in peerList.deviceList) {
                                    val peer = HashMap<String, String>()
                                    peer["name"] = device.deviceName
                                    peer["address"] = device.deviceAddress
                                    peer["isGroupOwner"] = device.isGroupOwner.toString()
                                    peer["status"] = device.status.toString()
                                    peers.add(peer)
                                }
                                Log.d(TAG_P2P, "Peers found: ${peers.size}")
                                runOnUiThread {
                                    wifiDirectChannel?.invokeMethod("onPeersChanged", peers)
                                }
                            }
                        }
                        WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                            val info = intent.getParcelableExtra<WifiP2pInfo>(WifiP2pManager.EXTRA_WIFI_P2P_INFO)
                            if (info != null) {
                                p2pConnected = info.groupFormed
                                p2pGroupOwner = info.isGroupOwner
                                p2pGroupOwnerAddress = info.groupOwnerAddress?.hostAddress ?: ""
                                Log.d(TAG_P2P, "P2P connection: formed=${info.groupFormed}, owner=${info.isGroupOwner}, addr=$p2pGroupOwnerAddress")
                                runOnUiThread {
                                    val connInfo = HashMap<String, Any>()
                                    connInfo["connected"] = p2pConnected
                                    connInfo["isGroupOwner"] = p2pGroupOwner
                                    connInfo["groupOwnerAddress"] = p2pGroupOwnerAddress
                                    wifiDirectChannel?.invokeMethod("onConnectionChanged", connInfo)
                                }
                            }
                        }
                    }
                }
            }
            registerReceiver(p2pReceiver, intentFilter)
            Log.d(TAG_P2P, "Wi-Fi Direct inicializado")
        } catch (e: Exception) {
            Log.e(TAG_P2P, "Error inicializando Wi-Fi Direct: ${e.message}")
        }
    }

    private fun initializeWifiP2p(result: MethodChannel.Result) {
        try {
            if (p2pManager == null) {
                p2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
                p2pChannel = p2pManager?.initialize(this, Looper.getMainLooper(), null)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("P2P_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun discoverP2pPeers(result: MethodChannel.Result) {
        try {
            p2pManager?.discoverPeers(p2pChannel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Log.d(TAG_P2P, "Descubrimiento P2P iniciado")
                    result.success(true)
                }
                override fun onFailure(reason: Int) {
                    Log.e(TAG_P2P, "Descubrimiento P2P fallido: reason=$reason")
                    result.error("P2P_ERROR", "Discovery failed: reason=$reason", null)
                }
            })
        } catch (e: Exception) {
            result.error("P2P_ERROR", e.message, null)
        }
    }

    private fun stopP2pDiscovery(result: MethodChannel.Result) {
        try {
            p2pManager?.stopPeerDiscovery(p2pChannel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() { result.success(true) }
                override fun onFailure(reason: Int) { result.error("P2P_ERROR", "Stop discovery failed: reason=$reason", null) }
            })
        } catch (e: Exception) {
            result.error("P2P_ERROR", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectP2pPeer(call: MethodCall, result: MethodChannel.Result) {
        try {
            val address = call.argument<String>("address") ?: ""
            if (address.isEmpty()) {
                result.error("P2P_ERROR", "Device address required", null)
                return
            }
            val config = WifiP2pConfig.Builder()
                .setDeviceAddress(android.net.MacAddress.fromString(address))
                .build()
            p2pManager?.connect(p2pChannel, config, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Log.d(TAG_P2P, "Conectando a $address...")
                    result.success(true)
                }
                override fun onFailure(reason: Int) {
                    Log.e(TAG_P2P, "Conexion P2P fallida: reason=$reason")
                    result.error("P2P_ERROR", "Connect failed: reason=$reason", null)
                }
            })
        } catch (e: Exception) {
            // Fallback for older APIs
            try {
                @Suppress("DEPRECATION")
                val address = call.argument<String>("address") ?: ""
                val config = WifiP2pConfig()
                config.deviceAddress = address
                config.groupOwnerIntent = 0 // Prefer other device as group owner
                p2pManager?.connect(p2pChannel, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { result.success(true) }
                    override fun onFailure(reason: Int) { result.error("P2P_ERROR", "Connect failed: reason=$reason", null) }
                })
            } catch (e2: Exception) {
                result.error("P2P_ERROR", e2.message, null)
            }
        }
    }

    private fun disconnectP2p(result: MethodChannel.Result) {
        try {
            p2pManager?.removeGroup(p2pChannel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    p2pConnected = false
                    p2pGroupOwner = false
                    p2pGroupOwnerAddress = ""
                    result.success(true)
                }
                override fun onFailure(reason: Int) { result.error("P2P_ERROR", "Disconnect failed: reason=$reason", null) }
            })
        } catch (e: Exception) {
            result.error("P2P_ERROR", e.message, null)
        }
    }

    private fun startP2pServer(result: MethodChannel.Result) {
        try {
            if (p2pServerSocket != null) {
                result.success(true)
                return
            }
            p2pServerThread = Thread {
                try {
                    p2pServerSocket = ServerSocket(P2P_PORT)
                    Log.d(TAG_P2P, "Servidor P2P TCP iniciado en puerto $P2P_PORT")
                    while (!Thread.currentThread().isInterrupted) {
                        try {
                            val client = p2pServerSocket?.accept() ?: break
                            val reader = BufferedReader(InputStreamReader(client.getInputStream()))
                            val message = reader.readLine()
                            if (message != null) {
                                Log.d(TAG_P2P, "Mensaje P2P recibido: ${message.length} chars")
                                runOnUiThread {
                                    wifiDirectChannel?.invokeMethod("onP2pMessage", message)
                                }
                            }
                            client.close()
                        } catch (e: Exception) {
                            if (!Thread.currentThread().isInterrupted) {
                                Log.e(TAG_P2P, "Error conexion P2P: ${e.message}")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG_P2P, "Error servidor P2P: ${e.message}")
                }
            }
            p2pServerThread?.start()
            result.success(true)
        } catch (e: Exception) {
            result.error("P2P_ERROR", e.message, null)
        }
    }

    private fun stopP2pServer(result: MethodChannel.Result) {
        try {
            p2pServerThread?.interrupt()
            p2pServerSocket?.close()
            p2pServerSocket = null
            p2pServerThread = null
            result.success(true)
        } catch (e: Exception) {
            result.error("P2P_ERROR", e.message, null)
        }
    }

    private fun sendP2pMessage(call: MethodCall, result: MethodChannel.Result) {
        try {
            val host = call.argument<String>("host") ?: p2pGroupOwnerAddress
            val message = call.argument<String>("message") ?: ""
            if (host.isEmpty() || message.isEmpty()) {
                result.error("P2P_ERROR", "Host y mensaje requeridos", null)
                return
            }
            Thread {
                try {
                    val socket = Socket(host, P2P_PORT)
                    val writer = PrintWriter(socket.getOutputStream(), true)
                    writer.println(message)
                    writer.flush()
                    socket.close()
                    Log.d(TAG_P2P, "Mensaje P2P enviado a $host ($P2P_PORT)")
                    runOnUiThread { result.success(true) }
                } catch (e: Exception) {
                    Log.e(TAG_P2P, "Error enviando P2P: ${e.message}")
                    runOnUiThread { result.error("P2P_ERROR", e.message, null) }
                }
            }.start()
        } catch (e: Exception) {
            result.error("P2P_ERROR", e.message, null)
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
        try {
            p2pServerThread?.interrupt()
            p2pServerSocket?.close()
        } catch (_: Exception) {}
        try {
            if (p2pReceiver != null) unregisterReceiver(p2pReceiver)
        } catch (_: Exception) {}
        try {
            p2pManager?.removeGroup(p2pChannel, null)
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
