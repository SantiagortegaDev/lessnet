package PACKAGE_PLACEHOLDER

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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

    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Buffer for incoming messages (until null terminator)
    private val messageBuffer = mutableListOf<Byte>()

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
        try {
            val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val btAdapter = btManager?.adapter
            if (btAdapter == null || !btAdapter.isEnabled) return false

            val adv = btAdapter.bluetoothLeAdvertiser
            return adv != null && btAdapter.isMultipleAdvertisementSupported
        } catch (e: Exception) {
            return false
        }
    }

    private fun startAdvertising(result: MethodChannel.Result) {
        try {
            bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothAdapter = bluetoothManager?.adapter

            if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
                Log.e(TAG, "Bluetooth no activado o adaptador null")
                result.error("BT_ERROR", "Bluetooth no esta activado", null)
                return
            }

            advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            if (advertiser == null) {
                Log.e(TAG, "BLE Advertiser no disponible en este dispositivo")
                result.error("ADV_ERROR", "Este dispositivo NO soporta BLE advertising. Muchos celulares OPPO, Realme y gamas bajas no lo soportan. Usa este celular para BUSCAR.", null)
                return
            }

            Log.d(TAG, "Iniciando GATT server con UUID: $SERVICE_UUID")
            if (!startGattServer()) {
                Log.e(TAG, "Fallo al crear GATT server")
                result.error("GATT_ERROR", "No se pudo crear el servidor GATT", null)
                return
            }

            // Use LOW_LATENCY for first 30s for fast discovery, then switch is handled
            // by the system. LOW_POWER is more battery-friendly but slower to discover.
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()

            Log.d(TAG, "Iniciando advertising con service UUID: $SERVICE_UUID")
            advertiser?.startAdvertising(settings, data, advertiseCallback)
            isCurrentlyAdvertising = true
            result.success(true)
        } catch (e: Exception) {
            isCurrentlyAdvertising = false
            result.error("ADV_ERROR", e.message, null)
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.d(TAG, "Advertising iniciado exitosamente (mode=${settingsInEffect.mode}, txPower=${settingsInEffect.txPowerLevel})")
            mainHandler.post {
                channel?.invokeMethod("onAdvertiseStatus", true)
            }
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "Advertising fallo con errorCode=$errorCode (1=DATA_TOO_LARGE, 2=TOO_MANY_ADVERTISERS, 3=INTERNAL_ERROR, 4=FEATURE_UNSUPPORTED)")
            isCurrentlyAdvertising = false
            mainHandler.post {
                channel?.invokeMethod("onAdvertiseStatus", false)
            }
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
                messageBuffer.clear()
                isSending = false
                try {
                    advertiser?.stopAdvertising(advertiseCallback)
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
                messageBuffer.clear()
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
                    if (messageBuffer.isNotEmpty()) {
                        val completeMessage = String(messageBuffer.toByteArray(), Charsets.UTF_8)
                        messageBuffer.clear()
                        mainHandler.post {
                            channel?.invokeMethod("onDataReceived", completeMessage)
                        }
                    }
                } else {
                    if (preparedWrite && offset > 0) {
                        while (messageBuffer.size < offset) {
                            messageBuffer.add(0)
                        }
                        for (i in value.indices) {
                            val pos = offset + i
                            if (pos < messageBuffer.size) {
                                messageBuffer[pos] = value[i]
                            } else {
                                messageBuffer.add(value[i])
                            }
                        }
                    } else {
                        for (b in value) {
                            messageBuffer.add(b)
                        }
                    }
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

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()

            advertiser?.startAdvertising(settings, data, advertiseCallback)
            isCurrentlyAdvertising = true
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
                advertiser?.stopAdvertising(advertiseCallback)
            } catch (e: Exception) {}
            try {
                gattServer?.close()
            } catch (e: Exception) {}
            gattServer = null
            isCurrentlyAdvertising = false
            isSending = false
            connectedDevice = null
            notificationsEnabled = false
            messageBuffer.clear()
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_ERROR", e.message, null)
        }
    }

    fun cleanup() {
        try {
            advertiser?.stopAdvertising(advertiseCallback)
        } catch (e: Exception) {}
        try {
            gattServer?.close()
        } catch (e: Exception) {}
        isCurrentlyAdvertising = false
        isSending = false
        connectedDevice = null
    }
}
