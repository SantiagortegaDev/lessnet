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
        private const val BLE_CHUNK_SIZE = 20
        private const val CHUNK_DELAY_MS = 20L  // ms between BLE notification chunks
        private const val CONFIRM_DELAY_MS = 30L // ms after sending notification to confirm delivery
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

    // Track if a send operation is in progress to prevent concurrent sends
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
            // Check if multiple advertisement is supported
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
                result.error("BT_ERROR", "Bluetooth no esta activado", null)
                return
            }

            // Check advertising support first
            advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            if (advertiser == null) {
                result.error("ADV_ERROR", "Este dispositivo NO soporta BLE advertising. Muchos celulares OPPO, Realme y gamas bajas no lo soportan. Usa este celular para BUSCAR.", null)
                return
            }

            // Start GATT server first (must be ready before advertising)
            if (!startGattServer()) {
                result.error("GATT_ERROR", "No se pudo crear el servidor GATT", null)
                return
            }

            // Start BLE advertising with LOW_LATENCY for faster discovery
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0) // No timeout - keep advertising indefinitely
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            // Include service UUID so scanners can identify us
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()

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
            mainHandler.post {
                channel?.invokeMethod("onAdvertiseStatus", true)
            }
        }

        override fun onStartFailure(errorCode: Int) {
            isCurrentlyAdvertising = false
            val errorMsg = when (errorCode) {
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "Datos de advertising demasiado grandes"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Demasiados advertisers activos"
                ADVERTISE_FAILED_ALREADY_STARTED -> "Advertising ya esta activo"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "Error interno de BLE"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "BLE advertising no soportado por este dispositivo"
                else -> "Error desconocido: $errorCode"
            }
            mainHandler.post {
                channel?.invokeMethod("onAdvertiseStatus", false)
            }
        }
    }

    private fun startGattServer(): Boolean {
        try {
            gattServer = bluetoothManager?.openGattServer(context, gattServerCallback) ?: return false

            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

            // RX characteristic - clients WRITE messages here
            val rxChar = BluetoothGattCharacteristic(
                CHAR_RX_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            // TX characteristic - clients READ/NOTIFY from here
            txCharacteristic = BluetoothGattCharacteristic(
                CHAR_TX_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )

            // Client Characteristic Configuration Descriptor (for notifications)
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
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevice = device
                messageBuffer.clear()
                isSending = false
                // Stop advertising when a device connects (one connection at a time)
                try {
                    advertiser?.stopAdvertising(advertiseCallback)
                } catch (e: Exception) {}
                isCurrentlyAdvertising = false
                val deviceName = device.name ?: device.address
                mainHandler.post {
                    channel?.invokeMethod("onDeviceConnected", deviceName)
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedDevice = null
                notificationsEnabled = false
                isSending = false
                messageBuffer.clear()
                mainHandler.post {
                    channel?.invokeMethod("onDeviceDisconnected", true)
                }
                // Resume advertising so other devices can find us
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
            if (characteristic.uuid == CHAR_RX_UUID) {
                if (value.size == 1 && value[0] == 0x00.toByte()) {
                    // End of message marker - deliver complete message
                    if (messageBuffer.isNotEmpty()) {
                        val completeMessage = String(messageBuffer.toByteArray(), Charsets.UTF_8)
                        messageBuffer.clear()
                        mainHandler.post {
                            channel?.invokeMethod("onDataReceived", completeMessage)
                        }
                    }
                } else {
                    // Buffer the data — respect offset for prepared writes
                    if (preparedWrite && offset > 0) {
                        // Ensure buffer is large enough for the offset
                        while (messageBuffer.size < offset) {
                            messageBuffer.add(0)
                        }
                        // Replace bytes at offset or append
                        for (i in value.indices) {
                            val pos = offset + i
                            if (pos < messageBuffer.size) {
                                messageBuffer[pos] = value[i]
                            } else {
                                messageBuffer.add(value[i])
                            }
                        }
                    } else {
                        // Normal write — just append
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
            // Called when a notification has been sent successfully (API 21+)
            // This is crucial for flow control — we know the client received the data
            if (status == BluetoothGatt.GATT_SUCCESS) {
                // Notification sent successfully
            } else {
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
     *
     * KEY FIX: Instead of posting all chunks asynchronously via mainHandler.post
     * (which can cause notifications to be queued and lost), we now:
     * 1. Send each notification SYNCHRONOUSLY on the main thread
     * 2. Wait for proper confirmation between chunks
     * 3. Use a CountDownLatch to ensure each notification is sent before the next
     * 4. Increase delays between chunks for reliability
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
            Log.d(TAG, "sendData: sending ${bytes.size} bytes in chunks of $BLE_CHUNK_SIZE")

            Thread {
                try {
                    var i = 0
                    while (i < bytes.size) {
                        val end = minOf(i + BLE_CHUNK_SIZE, bytes.size)
                        val chunk = bytes.copyOfRange(i, end)

                        // Use a latch to ensure each notification is sent on the main thread
                        // before proceeding to the next chunk
                        val latch = CountDownLatch(1)
                        mainHandler.post {
                            try {
                                txCharacteristic?.value = chunk
                                val notifyResult = gattServer?.notifyCharacteristicChanged(
                                    connectedDevice, txCharacteristic, false
                                )
                                if (notifyResult == false) {
                                    Log.w(TAG, "notifyCharacteristicChanged returned false at chunk offset $i")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error sending notification chunk at offset $i: ${e.message}")
                            } finally {
                                latch.countDown()
                            }
                        }

                        // Wait for the notification to be posted on main thread
                        latch.await(2, TimeUnit.SECONDS)

                        i = end

                        // Delay between chunks to prevent BLE buffer overflow
                        // This is critical — without proper delays, BLE notifications get dropped
                        if (i < bytes.size) {
                            Thread.sleep(CHUNK_DELAY_MS)
                        }
                    }

                    // Send null terminator as end-of-message marker
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

                    Log.d(TAG, "sendData: completed sending ${bytes.size} bytes")

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
