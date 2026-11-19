package com.muhammad.gtaremote

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppQosSettings
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * Phone ko Bluetooth HID keyboard banane wala hissa.
 *
 * Android ke [BluetoothHidDevice] API (Android 9+) se phone khud ko aik
 * standard Bluetooth keyboard register karta hai — laptop par koi program
 * install nahi hota, Windows ka apna driver kaam karta hai.
 *
 * Dart side se rabta:
 * - MethodChannel "gta_remote/hid" — commands (register, connect, report…)
 * - EventChannel "gta_remote/hid_events" — haqiqi registration/connection
 *   state, jo Android ke callbacks se aati hai (andaza kabhi nahi).
 *
 * Report format (boot keyboard): 8 bytes —
 * byte 0 = modifier (Left Shift = 0x02), byte 1 = 0, bytes 2..7 = keycodes.
 */
class HidKeyboardManager(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val METHOD_CHANNEL = "gta_remote/hid"
        private const val EVENT_CHANNEL = "gta_remote/hid_events"
        private const val REPORT_ID = 1

        private const val REQ_PERMISSIONS = 9401
        private const val REQ_ENABLE_BT = 9402
        private const val REQ_DISCOVERABLE = 9403

        /** Standard boot-keyboard report descriptor (proven format). */
        private val REPORT_DESCRIPTOR: ByteArray = descriptorBytes(
            0x05, 0x01, // Usage Page (Generic Desktop)
            0x09, 0x06, // Usage (Keyboard)
            0xA1, 0x01, // Collection (Application)
            0x85, 0x01, //   Report ID (1)
            0x05, 0x07, //   Usage Page (Key Codes)
            0x19, 0xE0, //   Usage Minimum (224)
            0x29, 0xE7, //   Usage Maximum (231)
            0x15, 0x00, //   Logical Minimum (0)
            0x25, 0x01, //   Logical Maximum (1)
            0x75, 0x01, //   Report Size (1)
            0x95, 0x08, //   Report Count (8)
            0x81, 0x02, //   Input (Data, Var, Abs) — modifier byte
            0x95, 0x01, //   Report Count (1)
            0x75, 0x08, //   Report Size (8)
            0x81, 0x01, //   Input (Constant) — reserved byte
            0x95, 0x05, //   Report Count (5)
            0x75, 0x01, //   Report Size (1)
            0x05, 0x08, //   Usage Page (LEDs)
            0x19, 0x01, //   Usage Minimum (1)
            0x29, 0x05, //   Usage Maximum (5)
            0x91, 0x02, //   Output (Data, Var, Abs) — LED report
            0x95, 0x01, //   Report Count (1)
            0x75, 0x03, //   Report Size (3)
            0x91, 0x01, //   Output (Constant) — LED padding
            0x95, 0x06, //   Report Count (6)
            0x75, 0x08, //   Report Size (8)
            0x15, 0x00, //   Logical Minimum (0)
            0x25, 0x65, //   Logical Maximum (101)
            0x05, 0x07, //   Usage Page (Key Codes)
            0x19, 0x00, //   Usage Minimum (0)
            0x29, 0x65, //   Usage Maximum (101)
            0x81, 0x00, //   Input (Data, Array) — 6 keycodes
            0xC0        // End Collection
        )

        private fun descriptorBytes(vararg values: Int): ByteArray =
            ByteArray(values.size) { index -> values[index].toByte() }

        private val SDP_SETTINGS = BluetoothHidDeviceAppSdpSettings(
            "GTA Remote",
            "GTA Remote Bluetooth keyboard",
            "GTA Remote",
            BluetoothHidDevice.SUBCLASS1_KEYBOARD,
            REPORT_DESCRIPTOR
        )

        private val QOS_SETTINGS = BluetoothHidDeviceAppQosSettings(
            BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
            800, 9, 0, 11250,
            BluetoothHidDeviceAppQosSettings.MAX
        )
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val manager =
            activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        manager?.adapter
    }

    private val mainExecutor: Executor =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            activity.mainExecutor
        } else {
            Executor { command -> activity.runOnUiThread(command) }
        }

    private var hidDevice: BluetoothHidDevice? = null
    private var isRegistered = false
    private var connectionState: Int = BluetoothProfile.STATE_DISCONNECTED
    private var connectedDevice: BluetoothDevice? = null
    private var targetDevice: BluetoothDevice? = null

    // Registration ka intezar karne wale Dart futures. Aik se zyada ho
    // sakte hain (screen khulte hi early-register + CONNECT par dobara
    // request) — sab ko aik hi callback se jawab milta hai, taake koi
    // request "busy" par hamesha ke liye atak na jaye.
    private val pendingRegisterResults = mutableListOf<MethodChannel.Result>()
    private var registerCallInFlight = false
    private var registerCallStartedAtMs = 0L
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingEnableResult: MethodChannel.Result? = null
    private var pendingDiscoverableResult: MethodChannel.Result? = null

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            hidDevice = proxy as? BluetoothHidDevice
            // Agar registration proxy ka intezar kar rahi thi to ab karo.
            if (pendingRegisterResults.isNotEmpty() && !isRegistered &&
                !registerCallInFlight
            ) {
                doRegister()
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            hidDevice = null
            isRegistered = false
            connectionState = BluetoothProfile.STATE_DISCONNECTED
            connectedDevice = null
            targetDevice = null
            // Intezar karne walo ko latka hua mat chhoro — warna agli
            // registration hamesha ke liye atak jayegi.
            failPendingRegisters(
                "Bluetooth service band ho gayi. Bluetooth off karke dobara on karo, phir koshish karo."
            )
            emitAppStatus()
            emitConnection(null, BluetoothProfile.STATE_DISCONNECTED)
        }
    }

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(
            pluggedDevice: BluetoothDevice?,
            registered: Boolean
        ) {
            isRegistered = registered
            emitAppStatus()
            if (registered) {
                completePendingRegisters()
            } else {
                failPendingRegisters(
                    "Registration band ho gayi. Koi aur remote/keyboard app Bluetooth keyboard use kar rahi ho sakti hai — use band karke dobara koshish karo."
                )
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
            connectionState = state
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> connectedDevice = device
                BluetoothProfile.STATE_DISCONNECTED -> {
                    connectedDevice = null
                    targetDevice = null
                }
            }
            emitConnection(device, state)
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
                emitAppStatus()
                emitConnection(connectedDevice, connectionState)
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        requestHidProxy()
    }

    private fun requestHidProxy() {
        try {
            bluetoothAdapter?.getProfileProxy(
                activity,
                profileListener,
                BluetoothProfile.HID_DEVICE
            )
        } catch (e: SecurityException) {
            // Permission abhi nahi mili — registerApp ke waqt dobara koshish hogi.
        }
    }

    // -------------------------------------------------------------------------
    // MethodChannel
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermissions" -> result.success(hasConnectPermission())
            "requestPermissions" -> requestPermissions(result)
            "isBluetoothEnabled" -> result.success(bluetoothAdapter?.isEnabled == true)
            "requestEnableBluetooth" -> requestEnableBluetooth(result)
            "openBluetoothSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("settings_failed", "Bluetooth settings nahi khul sakin.", null)
                }
            }
            "openAppSettings" -> {
                // Permission hamesha ke liye band ho to user ko app ki
                // apni Settings par bhejo (Nearby devices → Allow).
                try {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.fromParts(
                            "package",
                            activity.packageName,
                            null
                        )
                    )
                    activity.startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error(
                        "settings_failed",
                        "App settings nahi khul sakin. Phone ki Settings → Apps → GTA Remote → Permissions se Bluetooth allow karo.",
                        null
                    )
                }
            }
            "makeDiscoverable" -> makeDiscoverable(result)
            "getBondedDevices" -> result.success(bondedDevices())
            "registerApp" -> registerApp(result)
            "unregisterApp" -> {
                unregisterInternal()
                result.success(true)
            }
            "connect" -> connect(call.argument<String>("address"), result)
            "disconnect" -> {
                disconnectInternal()
                result.success(true)
            }
            "sendReport" -> sendReport(call, result)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Permissions
    // -------------------------------------------------------------------------

    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(mapOf("connect" to true, "advertise" to true))
            return
        }
        if (hasConnectPermission()) {
            result.success(mapOf("connect" to true, "advertise" to true))
            return
        }
        if (pendingPermissionResult != null) {
            result.success(mapOf("connect" to false, "advertise" to false))
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ),
            REQ_PERMISSIONS
        )
    }

    /** MainActivity se forward hota hai. True = hum ne handle kar liya. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQ_PERMISSIONS) return false
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        val connectGranted =
            grantResults.getOrNull(0) == PackageManager.PERMISSION_GRANTED
        val advertiseGranted =
            grantResults.getOrNull(1) == PackageManager.PERMISSION_GRANTED
        result.success(
            mapOf("connect" to connectGranted, "advertise" to advertiseGranted)
        )
        return true
    }

    // -------------------------------------------------------------------------
    // Bluetooth on karna / discoverable banana
    // -------------------------------------------------------------------------

    private fun requestEnableBluetooth(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("no_bluetooth", "Is phone me Bluetooth nahi hai.", null)
            return
        }
        if (adapter.isEnabled) {
            result.success(true)
            return
        }
        if (pendingEnableResult != null) {
            result.success(false)
            return
        }
        pendingEnableResult = result
        try {
            activity.startActivityForResult(
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                REQ_ENABLE_BT
            )
        } catch (e: Exception) {
            pendingEnableResult = null
            result.error(
                "enable_failed",
                "Bluetooth on karne wali screen nahi khul saki. Phone ki Settings se Bluetooth on karke dobara koshish karo.",
                null
            )
        }
    }

    private fun makeDiscoverable(result: MethodChannel.Result) {
        if (bluetoothAdapter == null) {
            result.error("no_bluetooth", "Is phone me Bluetooth nahi hai.", null)
            return
        }
        if (pendingDiscoverableResult != null) {
            result.success(false)
            return
        }
        pendingDiscoverableResult = result
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
            putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
        }
        try {
            activity.startActivityForResult(intent, REQ_DISCOVERABLE)
        } catch (e: Exception) {
            pendingDiscoverableResult = null
            result.error(
                "discoverable_failed",
                "Discoverable wali screen nahi khul saki. Dobara koshish karo.",
                null
            )
        }
    }

    /** MainActivity se forward hota hai. True = hum ne handle kar liya. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        when (requestCode) {
            REQ_ENABLE_BT -> {
                val result = pendingEnableResult ?: return true
                pendingEnableResult = null
                result.success(resultCode == Activity.RESULT_OK)
                return true
            }
            REQ_DISCOVERABLE -> {
                val result = pendingDiscoverableResult ?: return true
                pendingDiscoverableResult = null
                // Qubool ho to resultCode duration (seconds) hota hai, 0 = cancel.
                result.success(resultCode != Activity.RESULT_CANCELED)
                return true
            }
        }
        return false
    }

    // -------------------------------------------------------------------------
    // Devices
    // -------------------------------------------------------------------------

    private fun bondedDevices(): List<Map<String, Any>> {
        if (!hasConnectPermission()) return emptyList()
        val devices = try {
            bluetoothAdapter?.bondedDevices ?: emptySet()
        } catch (e: SecurityException) {
            emptySet()
        }
        return devices.map { device ->
            val name = try {
                device.name ?: device.address
            } catch (e: SecurityException) {
                device.address
            }
            // Device ki qisam (computer / phone / audio…) — UI isi se
            // laptop ko earbuds waghera se alag pehchanti hai, warna
            // beginner ko list me sab aik jaisa lagta hai.
            val majorClass = try {
                device.bluetoothClass?.majorDeviceClass ?: 0
            } catch (e: SecurityException) {
                0
            }
            mapOf(
                "name" to name,
                "address" to device.address,
                "majorClass" to majorClass
            )
        }
    }

    // -------------------------------------------------------------------------
    // Registration / connection
    // -------------------------------------------------------------------------

    private fun registerApp(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error(
                "old_android",
                "Bluetooth keyboard mode ke liye Android 9 ya naya chahiye.",
                null
            )
            return
        }
        if (!hasConnectPermission()) {
            result.error(
                "no_permission",
                "Bluetooth permission nahi mili. Pehle Allow karo.",
                null
            )
            return
        }
        if (isRegistered) {
            result.success(true)
            return
        }
        // Registration pehle se chal rahi ho to ye request bhi usi ke
        // saath line me lag jati hai — "busy" error nahi milta, aur aik
        // hi asal callback sab ko jawab de deta hai.
        pendingRegisterResults.add(result)
        if (registerCallInFlight) {
            // Kuch phones par registerApp qubool hone ke bawajood
            // callback kabhi nahi aata — purani call buhat purani ho
            // gayi ho to aik dafa dobara bhej do, warna sab intezar
            // karne wale hamesha ke liye atak jayenge.
            val elapsed = android.os.SystemClock.elapsedRealtime() -
                registerCallStartedAtMs
            if (elapsed > 4000) {
                doRegister()
            }
            return
        }
        if (hidDevice == null) {
            // Proxy abhi nahi aaya — aate hi doRegister chalega
            // (profileListener dekho).
            requestHidProxy()
            return
        }
        doRegister()
    }

    private fun doRegister() {
        val proxy = hidDevice
        if (proxy == null) {
            failPendingRegisters(
                "Bluetooth service tayyar nahi. Thodi dair baad dobara koshish karo."
            )
            return
        }
        registerCallInFlight = true
        registerCallStartedAtMs = android.os.SystemClock.elapsedRealtime()
        val accepted = try {
            proxy.registerApp(SDP_SETTINGS, null, QOS_SETTINGS, mainExecutor, hidCallback)
        } catch (e: SecurityException) {
            false
        }
        if (!accepted) {
            failPendingRegisters(
                "Registration shuru nahi ho saki. Koi aur remote app khuli ho to band karke dobara koshish karo."
            )
        }
        // Kamyabi ka asal jawab onAppStatusChanged callback dega.
    }

    /** Tamam intezar karne walo ko kamyabi ka jawab do. */
    private fun completePendingRegisters() {
        registerCallInFlight = false
        val waiting = pendingRegisterResults.toList()
        pendingRegisterResults.clear()
        for (result in waiting) {
            result.success(true)
        }
    }

    /** Tamam intezar karne walo ko nakami ka jawab do (koi latka na rahe). */
    private fun failPendingRegisters(message: String) {
        registerCallInFlight = false
        val waiting = pendingRegisterResults.toList()
        pendingRegisterResults.clear()
        for (result in waiting) {
            result.error("register_failed", message, null)
        }
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        val proxy = hidDevice
        if (proxy == null || !isRegistered) {
            result.error(
                "not_registered",
                "Pehle registration zaroori hai.",
                null
            )
            return
        }
        if (address.isNullOrBlank()) {
            result.error("bad_address", "Laptop select nahi hua.", null)
            return
        }
        val device = try {
            bluetoothAdapter?.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            null
        }
        if (device == null) {
            result.error("bad_address", "Laptop ka address ghalat hai.", null)
            return
        }
        // Pairing hi nahi hui (ya laptop se remove ho gayi) to connect
        // sirf waqt zaya karega — foran wazeh jawab do taake user pehle
        // pair kare.
        val bonded = try {
            device.bondState == BluetoothDevice.BOND_BONDED
        } catch (e: SecurityException) {
            true // Check na ho saka to connect ki koshish jaari rakho.
        }
        if (!bonded) {
            result.error(
                "not_paired",
                "Ye laptop is phone ke saath paired nahi hai. Pehle neeche wali guide se pair karo, phir CONNECT dabao.",
                null
            )
            return
        }
        // Pehle se connected/connecting ho to dobara connect call ki
        // zaroorat nahi — kuch phones par woh call false deti hai aur
        // Dart use nakami samajh leta hai. Asal haalat callback dega.
        if ((device == connectedDevice || device == targetDevice) &&
            (connectionState == BluetoothProfile.STATE_CONNECTED ||
                connectionState == BluetoothProfile.STATE_CONNECTING)
        ) {
            result.success(true)
            return
        }
        targetDevice = device
        val accepted = try {
            proxy.connect(device)
        } catch (e: SecurityException) {
            false
        }
        if (accepted) {
            result.success(true)
        } else {
            result.error(
                "connect_failed",
                "Connect shuru nahi ho saka. Laptop ki Bluetooth on hai, ye check karo.",
                null
            )
        }
    }

    private fun disconnectInternal() {
        val device = connectedDevice ?: targetDevice
        if (device != null) {
            sendZeroReport(device)
            try {
                hidDevice?.disconnect(device)
            } catch (e: SecurityException) {
                // Connection pehle hi band — koi baat nahi.
            }
        }
    }

    private fun unregisterInternal() {
        try {
            hidDevice?.unregisterApp()
        } catch (e: SecurityException) {
            // Pehle hi unregister — koi baat nahi.
        }
        isRegistered = false
        emitAppStatus()
    }

    // -------------------------------------------------------------------------
    // Reports
    // -------------------------------------------------------------------------

    private fun sendReport(call: MethodCall, result: MethodChannel.Result) {
        val proxy = hidDevice
        val device = connectedDevice
        if (proxy == null || device == null ||
            connectionState != BluetoothProfile.STATE_CONNECTED
        ) {
            result.success(false)
            return
        }
        val modifier = call.argument<Int>("modifier") ?: 0
        val keycodes = call.argument<List<Int>>("keycodes") ?: emptyList()
        val data = ByteArray(8)
        data[0] = modifier.toByte()
        data[1] = 0
        keycodes.take(6).forEachIndexed { index, code ->
            data[2 + index] = code.toByte()
        }
        val sent = try {
            proxy.sendReport(device, REPORT_ID, data)
        } catch (e: SecurityException) {
            false
        }
        result.success(sent)
    }

    private fun sendZeroReport(device: BluetoothDevice) {
        try {
            hidDevice?.sendReport(device, REPORT_ID, ByteArray(8))
        } catch (e: SecurityException) {
            // Link pehle hi band — zero report ki zaroorat nahi rahi.
        }
    }

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    /**
     * App background me jaye to (MainActivity.onPause se):
     * saari keys chhoro (zero report) — koi key atak nahi sakti.
     *
     * Registration background me bhi REHNE do: pairing confirm aur
     * discoverable consent jese system dialogs activity ko pause karte
     * hain — us waqt unregister karne se pairing ke doran laptop ko
     * keyboard service (SDP record) nazar nahi aati aur baad me HID
     * connect fail ho jata hai. Unregister sirf dispose aur explicit
     * disconnect par hota hai.
     */
    fun onHostPause() {
        connectedDevice?.let { sendZeroReport(it) }
    }

    fun dispose() {
        connectedDevice?.let { sendZeroReport(it) }
        unregisterInternal()
        try {
            val proxy = hidDevice
            if (proxy != null) {
                bluetoothAdapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, proxy)
            }
        } catch (e: Exception) {
            // Band hote waqt ki safai — error nazarandaz.
        }
        hidDevice = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    // -------------------------------------------------------------------------
    // Events -> Dart
    // -------------------------------------------------------------------------

    private fun emitAppStatus() {
        eventSink?.success(
            mapOf("event" to "appStatus", "registered" to isRegistered)
        )
    }

    private fun emitConnection(device: BluetoothDevice?, state: Int) {
        val stateName = when (state) {
            BluetoothProfile.STATE_CONNECTED -> "connected"
            BluetoothProfile.STATE_CONNECTING -> "connecting"
            BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
            else -> "disconnected"
        }
        val name = if (device == null) {
            null
        } else {
            try {
                device.name
            } catch (e: SecurityException) {
                null
            }
        }
        eventSink?.success(
            mapOf(
                "event" to "connection",
                "state" to stateName,
                "name" to name,
                "address" to device?.address
            )
        )
    }
}
