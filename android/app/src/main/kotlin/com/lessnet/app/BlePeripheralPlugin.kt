package com.lessnet.app

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class BlePeripheralPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        val CHAR_RX_UUID: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        val CHAR_TX_UUID: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val TAG = "BlePeripheralPlugin"
        private const val NOTIFY_CHUNK_SIZE = 200 // bytes per notification (MTU-safe)
        private const val NOTIFY_DELAY_MS = 10L   // ms between notifications
    }

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var connectedDevice: BluetoothDevice? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var isCurrentlyAdvertising = false
    private var legacyAdvertiseCallback: AdvertiseCallback? = null
    private var advertisingSetCallback: AdvertisingSetCallback? = null

    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Buffer for incoming messages (until null terminator)
    // Using ByteArrayOutputStream for O(1) append instead of O(n) mutableListOf<Byte>
    private val messageBuffer = ByteArrayOutputStream()

    // Track if notifications are enabled by the client
    private var notificationsEnabled = false

    // Track if a send operation is in progress
    private var isSending = false

    fun setChannel(ch: MethodChannel) {
        this.channel = ch
        ch.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> startAdvertising(result)
            "stopAdvertising" -> stopAdvertising(result)
            "sendData" -> {
                val data = call.argument<String>("data") ?: ""
                sendData(data, result)
            }
            "sendFile" -> {
                val data = call.argument<String>("data") ?: ""
                sendFile(data, result)
            }
            "isAdvertising" -> result.success(isCurrentlyAdvertising)
            "supportsAdvertising" -> {
                val supported = checkAdvertisingSupport()
                result.success(supported)
            }
            else -> result.notImplemented()
        }
    }

    private fun checkAdvertisingSupport(): Boolean {
        return try {
            val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val btAdapter = btManager?.adapter
            if (btAdapter == null || !btAdapter.isEnabled) return false
            // En Android 8+ siempre intentar, ignorar isMultipleAdvertisementSupported
            // (MediaTek y otros chipsets reportan false pero sí funcionan)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                return btAdapter.bluetoothLeAdvertiser != null
            }
            // Android < 8: respetar el flag
            btAdapter.bluetoothLeAdvertiser != null &&
                btAdapter.isMultipleAdvertisementSupported
        } catch (e: Exception) { false }
    }

    private fun startAdvertising(result: MethodChannel.Result) {
        try {
            bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothAdapter = bluetoothManager?.adapter

            if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
                result.error("BT_ERROR", "Bluetooth no activado", null)
                return
            }

            // Verificar permiso BLUETOOTH_ADVERTISE en Android 12+
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                if (context.checkSelfPermission(
                        android.Manifest.permission.BLUETOOTH_ADVERTISE
                    ) != PackageManager.PERMISSION_GRANTED) {
                    result.error("ADV_ERROR",
                        "Falta permiso BLUETOOTH_ADVERTISE", null)
                    return
                }
            }

            if (!startGattServer()) {
                result.error("GATT_ERROR", "No se pudo crear GATT server", null)
                return
            }

            // Intentar advertising con fallback progresivo
            tryAdvertisingWithFallback(result)

        } catch (e: Exception) {
            isCurrentlyAdvertising = false
            result.error("ADV_ERROR", e.message, null)
        }
    }

    private fun tryAdvertisingWithFallback(result: MethodChannel.Result) {
        // Intento 1: Android 8+ AdvertisingSet API (mas compatible)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            tryAdvertisingSetApi(result)
            return
        }
        // Intento 2: Legacy API sin nombre (payload minimo)
        tryLegacyAdvertising(result)
    }

    // Intento 1: AdvertisingSet API (Android 8+) - mas compatible con
    // chipsets MediaTek y Qualcomm que rechazan la API legacy
    @androidx.annotation.RequiresApi(android.os.Build.VERSION_CODES.O)
    private fun tryAdvertisingSetApi(result: MethodChannel.Result) {
        try {
            val setAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            if (setAdvertiser == null) {
                tryLegacyAdvertising(result)
                return
            }

            val params = AdvertisingSetParameters.Builder()
                .setLegacyMode(true)   // compatible con todos los scanners
                .setConnectable(true)
                .setInterval(AdvertisingSetParameters.INTERVAL_LOW)
                .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_HIGH)
                .build()

            // Payload minimo: SOLO el UUID (sin nombre = ahorra 12 bytes)
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()

            // Scan response lleva el nombre (no cuenta para el limite principal)
            val scanResponse = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .build()

            val setCallback = object : AdvertisingSetCallback() {
                override fun onAdvertisingSetStarted(
                    set: AdvertisingSet?,
                    txPower: Int,
                    status: Int
                ) {
                    if (status == AdvertisingSetCallback.ADVERTISE_SUCCESS) {
                        Log.d(TAG, "AdvertisingSet API exitoso")
                        isCurrentlyAdvertising = true
                        mainHandler.post {
                            channel?.invokeMethod("onAdvertiseStatus", true)
                            result.success(true)
                        }
                    } else {
                        Log.w(TAG, "AdvertisingSet fallo status=$status, intentando legacy")
                        mainHandler.post { tryLegacyAdvertising(result) }
                    }
                }
            }
            advertisingSetCallback = setCallback
            setAdvertiser.startAdvertisingSet(
                params, data, scanResponse, null, null, setCallback
            )
        } catch (e: Exception) {
            Log.w(TAG, "AdvertisingSet API excepcion: ${e.message}, intentando legacy")
            tryLegacyAdvertising(result)
        }
    }

    // Intento 2: Legacy API sin nombre del dispositivo
    private fun tryLegacyAdvertising(result: MethodChannel.Result) {
        try {
            advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            if (advertiser == null) {
                Log.e(TAG, "Advertiser null en ambos intentos")
                result.error("ADV_ERROR",
                    "Este dispositivo no soporta BLE advertising", null)
                return
            }

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            // SIN nombre del dispositivo = payload pequeno = mas compatible
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()

            val scanResponse = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .build()

            val cb = object : AdvertiseCallback() {
                override fun onStartSuccess(s: AdvertiseSettings) {
                    Log.d(TAG, "Legacy advertising exitoso")
                    isCurrentlyAdvertising = true
                    mainHandler.post {
                        channel?.invokeMethod("onAdvertiseStatus", true)
                        result.success(true)
                    }
                }
                override fun onStartFailure(errorCode: Int) {
                    Log.e(TAG, "Legacy advertising fallo: errorCode=$errorCode")
                    isCurrentlyAdvertising = false
                    mainHandler.post {
                        channel?.invokeMethod("onAdvertiseStatus", false)
                        result.error("ADV_ERROR",
                            "Advertising fallo (codigo $errorCode). " +
                            "Este dispositivo no puede ser visible.", null)
                    }
                }
            }
            advertiser?.startAdvertising(settings, data, scanResponse, cb)
            // Guarda referencia para poder detenerlo
            legacyAdvertiseCallback = cb

        } catch (e: Exception) {
            isCurrentlyAdvertising = false
            result.error("ADV_ERROR", e.message, null)
        }
    }

    private fun startGattServer(): Boolean {
        try {
            gattServer = bluetoothManager?.openGattServer(context, gattServerCallback) ?: return false

            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

            val rxChar = BluetoothGattCharacteristic(
                CHAR_RX_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            txCharacteristic = BluetoothGattCharacteristic(
                CHAR_TX_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )

            val cccd = BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
            txCharacteristic?.addDescriptor(cccd)

            service.addCharacteristic(rxChar)
            service.addCharacteristic(txCharacteristic!!)

            gattServer?.addService(service)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            Log.d(TAG, "onConnectionStateChange: ${device.address} status=$status newState=$newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevice = device
                messageBuffer.reset()
                isSending = false
                try {
                    if (advertisingSetCallback != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertisingSet(advertisingSetCallback)
                    }
                } catch (e: Exception) {}
                try {
                    advertiser?.stopAdvertising(legacyAdvertiseCallback)
                } catch (e: Exception) {}
                isCurrentlyAdvertising = false
                val deviceName = device.name ?: device.address
                Log.d(TAG, "Dispositivo CONECTADO: $deviceName")
                mainHandler.post {
                    channel?.invokeMethod("onDeviceConnected", deviceName)
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "Dispositivo DESCONECTADO: ${device.address}")
                connectedDevice = null
                notificationsEnabled = false
                isSending = false
                messageBuffer.reset()
                mainHandler.post {
                    channel?.invokeMethod("onDeviceDisconnected", true)
                }
                restartAdvertising()
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            Log.d(TAG, "onCharacteristicWriteRequest: char=${characteristic.uuid} offset=$offset len=${value.size} prepared=$preparedWrite")
            if (characteristic.uuid == CHAR_RX_UUID) {
                if (value.size == 1 && value[0] == 0x00.toByte()) {
                    // Null terminator: message complete
                    if (messageBuffer.size() > 0) {
                        val completeMessage = messageBuffer.toString(Charsets.UTF_8.name())
                        messageBuffer.reset()
                        Log.d(TAG, "Mensaje completo recibido: ${completeMessage.length} chars")
                        mainHandler.post {
                            channel?.invokeMethod("onDataReceived", completeMessage)
                        }
                    }
                } else {
                    // Append data to buffer
                    if (preparedWrite && offset > 0) {
                        // Handle prepared write with offset
                        val currentSize = messageBuffer.size()
                        if (currentSize < offset) {
                            // Pad with zeros to reach offset
                            val padding = ByteArray(offset - currentSize)
                            messageBuffer.write(padding)
                        }
                        messageBuffer.write(value, offset.coerceAtMost(currentSize), value.size - offset.coerceAtMost(currentSize))
                    } else {
                        messageBuffer.write(value)
                    }
                    Log.d(TAG, "Buffer: ${messageBuffer.size()} bytes acumulados")
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor
        ) {
            if (descriptor.uuid == CCCD_UUID) {
                val value = if (notificationsEnabled)
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                else
                    BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
            } else {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (descriptor.uuid == CCCD_UUID) {
                notificationsEnabled = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                Log.d(TAG, "Notificaciones ${if (notificationsEnabled) "ACTIVADAS" else "DESACTIVADAS"} por ${device.address}")
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, characteristic.value)
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            Log.d(TAG, "MTU changed to: $mtu")
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                Log.w(TAG, "Notification send failed with status: $status")
            }
        }
    }

    private fun restartAdvertising() {
        try {
            if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) return
            advertiser = bluetoothAdapter?.bluetoothLeAdvertiser ?: return

            // Try AdvertisingSet API on Android 8+
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                try {
                    val params = AdvertisingSetParameters.Builder()
                        .setLegacyMode(true)
                        .setConnectable(true)
                        .setInterval(AdvertisingSetParameters.INTERVAL_LOW)
                        .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_HIGH)
                        .build()

                    val data = AdvertiseData.Builder()
                        .setIncludeDeviceName(false)
                        .addServiceUuid(ParcelUuid(SERVICE_UUID))
                        .build()

                    val scanResponse = AdvertiseData.Builder()
                        .setIncludeDeviceName(true)
                        .build()

                    val setCallback = object : AdvertisingSetCallback() {
                        override fun onAdvertisingSetStarted(
                            set: AdvertisingSet?, txPower: Int, status: Int
                        ) {
                            if (status == AdvertisingSetCallback.ADVERTISE_SUCCESS) {
                                Log.d(TAG, "Restart: AdvertisingSet API exitoso")
                                isCurrentlyAdvertising = true
                                mainHandler.post {
                                    channel?.invokeMethod("onAdvertiseStatus", true)
                                }
                            } else {
                                Log.w(TAG, "Restart: AdvertisingSet fallo, intentando legacy")
                                restartLegacyAdvertising()
                            }
                        }
                    }
                    advertisingSetCallback = setCallback
                    advertiser?.startAdvertisingSet(params, data, scanResponse, null, null, setCallback)
                    return
                } catch (e: Exception) {
                    Log.w(TAG, "Restart: AdvertisingSet excepcion: ${e.message}")
                }
            }

            // Fallback: Legacy API
            restartLegacyAdvertising()
        } catch (e: Exception) {
            isCurrentlyAdvertising = false
        }
    }

    private fun restartLegacyAdvertising() {
        try {
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()

            val scanResponse = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .build()

            val cb = object : AdvertiseCallback() {
                override fun onStartSuccess(s: AdvertiseSettings) {
                    Log.d(TAG, "Restart: Legacy advertising exitoso")
                    isCurrentlyAdvertising = true
                    mainHandler.post {
                        channel?.invokeMethod("onAdvertiseStatus", true)
                    }
                }
                override fun onStartFailure(errorCode: Int) {
                    Log.e(TAG, "Restart: Legacy advertising fallo: errorCode=$errorCode")
                    isCurrentlyAdvertising = false
                }
            }
            legacyAdvertiseCallback = cb
            advertiser?.startAdvertising(settings, data, scanResponse, cb)
        } catch (e: Exception) {
            isCurrentlyAdvertising = false
        }
    }

    /**
     * Send data reliably over BLE notifications.
     * Uses CountDownLatch for synchronous notification sending.
     * Uses 200-byte chunks with 10ms delay for speed + reliability.
     */
    private fun sendData(data: String, result: MethodChannel.Result) {
        if (connectedDevice == null || txCharacteristic == null) {
            result.error("SEND_ERROR", "No hay dispositivo conectado", null)
            return
        }
        if (!notificationsEnabled) {
            result.error("SEND_ERROR", "El cliente no tiene notificaciones activadas", null)
            return
        }
        if (isSending) {
            result.error("SEND_ERROR", "Ya hay un envio en progreso", null)
            return
        }

        isSending = true

        try {
            val bytes = data.toByteArray(Charsets.UTF_8)
            Log.d(TAG, "sendData: sending ${bytes.size} bytes")

            Thread {
                try {
                    var i = 0
                    while (i < bytes.size) {
                        val end = minOf(i + NOTIFY_CHUNK_SIZE, bytes.size)
                        val chunk = bytes.copyOfRange(i, end)

                        val latch = CountDownLatch(1)
                        mainHandler.post {
                            try {
                                txCharacteristic?.value = chunk
                                gattServer?.notifyCharacteristicChanged(connectedDevice, txCharacteristic, false)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error sending notification at offset $i: ${e.message}")
                            } finally {
                                latch.countDown()
                            }
                        }

                        latch.await(2, TimeUnit.SECONDS)
                        i = end

                        if (i < bytes.size) {
                            Thread.sleep(NOTIFY_DELAY_MS)
                        }
                    }

                    // Null terminator
                    val termLatch = CountDownLatch(1)
                    mainHandler.post {
                        try {
                            txCharacteristic?.value = byteArrayOf(0x00)
                            gattServer?.notifyCharacteristicChanged(connectedDevice, txCharacteristic, false)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error sending terminator: ${e.message}")
                        } finally {
                            termLatch.countDown()
                        }
                    }
                    termLatch.await(2, TimeUnit.SECONDS)

                    Log.d(TAG, "sendData: completed ${bytes.size} bytes")
                    mainHandler.post {
                        isSending = false
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "sendData thread error: ${e.message}")
                    mainHandler.post {
                        isSending = false
                        result.error("SEND_ERROR", e.message, null)
                    }
                }
            }.start()
        } catch (e: Exception) {
            isSending = false
            result.error("SEND_ERROR", e.message, null)
        }
    }

    /**
     * Send file data with progress reporting.
     * Reports progress every 5% via onSendProgress callback.
     */
    private fun sendFile(data: String, result: MethodChannel.Result) {
        if (connectedDevice == null || txCharacteristic == null) {
            result.error("SEND_ERROR", "No hay dispositivo conectado", null)
            return
        }
        if (!notificationsEnabled) {
            result.error("SEND_ERROR", "El cliente no tiene notificaciones activadas", null)
            return
        }
        if (isSending) {
            result.error("SEND_ERROR", "Ya hay un envio en progreso", null)
            return
        }

        isSending = true

        try {
            val bytes = data.toByteArray(Charsets.UTF_8)
            val totalBytes = bytes.size
            Log.d(TAG, "sendFile: sending $totalBytes bytes with progress")

            Thread {
                try {
                    var i = 0
                    var lastReportedPercent = -1

                    while (i < bytes.size) {
                        val end = minOf(i + NOTIFY_CHUNK_SIZE, bytes.size)
                        val chunk = bytes.copyOfRange(i, end)

                        val latch = CountDownLatch(1)
                        mainHandler.post {
                            try {
                                txCharacteristic?.value = chunk
                                gattServer?.notifyCharacteristicChanged(connectedDevice, txCharacteristic, false)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error at offset $i: ${e.message}")
                            } finally {
                                latch.countDown()
                            }
                        }

                        latch.await(2, TimeUnit.SECONDS)
                        i = end

                        // Report progress every 5%
                        val percent = ((i * 100) / totalBytes / 5) * 5
                        if (percent != lastReportedPercent) {
                            lastReportedPercent = percent
                            val progress = i.toDouble() / totalBytes.toDouble()
                            mainHandler.post {
                                channel?.invokeMethod("onSendProgress", progress)
                            }
                        }

                        if (i < bytes.size) {
                            Thread.sleep(NOTIFY_DELAY_MS)
                        }
                    }

                    // Null terminator
                    val termLatch = CountDownLatch(1)
                    mainHandler.post {
                        try {
                            txCharacteristic?.value = byteArrayOf(0x00)
                            gattServer?.notifyCharacteristicChanged(connectedDevice, txCharacteristic, false)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error sending terminator: ${e.message}")
                        } finally {
                            termLatch.countDown()
                        }
                    }
                    termLatch.await(2, TimeUnit.SECONDS)

                    // Report 100%
                    mainHandler.post {
                        channel?.invokeMethod("onSendProgress", 1.0)
                    }

                    Log.d(TAG, "sendFile: completed $totalBytes bytes")
                    mainHandler.post {
                        isSending = false
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "sendFile thread error: ${e.message}")
                    mainHandler.post {
                        isSending = false
                        result.error("SEND_ERROR", e.message, null)
                    }
                }
            }.start()
        } catch (e: Exception) {
            isSending = false
            result.error("SEND_ERROR", e.message, null)
        }
    }

    private fun stopAdvertising(result: MethodChannel.Result) {
        try {
            try {
                if (advertisingSetCallback != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertisingSet(advertisingSetCallback)
                    advertisingSetCallback = null
                }
            } catch (e: Exception) {}
            try {
                advertiser?.stopAdvertising(legacyAdvertiseCallback)
                legacyAdvertiseCallback = null
            } catch (e: Exception) {}
            try {
                gattServer?.close()
            } catch (e: Exception) {}
            gattServer = null
            isCurrentlyAdvertising = false
            isSending = false
            connectedDevice = null
            notificationsEnabled = false
            messageBuffer.reset()
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_ERROR", e.message, null)
        }
    }

    fun cleanup() {
        try {
            if (advertisingSetCallback != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertisingSet(advertisingSetCallback)
            }
        } catch (e: Exception) {}
        try {
            advertiser?.stopAdvertising(legacyAdvertiseCallback)
        } catch (e: Exception) {}
        try {
            gattServer?.close()
        } catch (e: Exception) {}
        isCurrentlyAdvertising = false
        isSending = false
        connectedDevice = null
    }
}
