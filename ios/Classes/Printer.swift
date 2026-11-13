//
//  Printer.swift
//
//  One instance per Dart ZebraPrinter, on channel "ZebraPrinterObject<id>".
//  Bluetooth Classic only (External Accessory, protocol com.zebra.rawport).
//  Method, event, key and status names follow lib/zebra_printer.dart and the Android
//  implementation (android/src/main/java/com/rubdev/zebrautil/Printer.java, res/values/strings.xml).
//

import ExternalAccessory
import Flutter
import Foundation

private let zebraProtocol = "com.zebra.rawport"

// Android res/values/strings.xml, returned by getLocateValue and used as statuses.
private let androidStrings: [String: String] = [
    "disconnect": "Disconnected",
    "connected": "Connected",
    "connecting": "Connecting",
    "disconnecting": "Disconnecting",
    "scanning": "Scanning",
    "stopping_scan": "Stopping scan",
    "done": "Done",
    "disconnectColor": "R",
    "connectedColor": "G",
    "connectingColor": "Y",
    "sending_data": "Sending Data",
]

private let disconnectedStr = "Disconnected"
private let connectedStr = "Connected"
private let connectingStr = "Connecting"
private let disconnectingStr = "Disconnecting"
private let doneStr = "Done"
private let sendingDataStr = "Sending Data"
private let red = "R"
private let green = "G"
private let yellow = "Y"

class Printer {
    private var methodChannel: FlutterMethodChannel?

    // Blocking SDK calls (open, write, close) run here, one at a time.
    private let queue = DispatchQueue(label: "co.evreka.zebrautil.printer")

    #if !targetEnvironment(simulator)
    // Only touched on `queue`.
    private var connection: MfiBtPrinterConnection?
    #endif

    // Main thread only.
    private var connectedSerial: String?
    private var scanObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    private static let registerAccessoryNotifications: Void =
        EAAccessoryManager.shared().registerForLocalNotifications()

    static func getInstance(binaryMessenger: FlutterBinaryMessenger) -> Printer {
        let printer = Printer()
        let channel = FlutterMethodChannel(name: "ZebraPrinterObject" + printer.toString(), binaryMessenger: binaryMessenger)
        channel.setMethodCallHandler { [weak printer] call, result in
            guard let printer = printer else { return result(FlutterMethodNotImplemented) }
            printer.handle(call, result)
        }
        printer.methodChannel = channel
        return printer
    }

    func toString() -> String {
        return String(UInt(bitPattern: ObjectIdentifier(self)))
    }

    // Called on the main thread by Flutter. Every branch answers `result` exactly once.
    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "checkPermission":
            result(true)
        case "startScan":
            result(nil)
            startScan()
        case "stopScan":
            stopScan()
            result(nil)
        case "connectToPrinter":
            connect(address: args?["Address"] as? String, result: result)
        case "disconnect":
            disconnect(result: result)
        case "print":
            result(nil)
            if let text = args?["Data"] as? String { printData(text) }
        case "getLocateValue":
            result(androidStrings[args?["ResourceKey"] as? String ?? ""] ?? "")
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: Discovery

    private func startScan() {
        _ = Printer.registerAccessoryNotifications
        if scanObserver == nil {
            scanObserver = NotificationCenter.default.addObserver(
                forName: .EAAccessoryDidConnect, object: nil, queue: .main
            ) { [weak self] note in
                if let accessory = note.userInfo?[EAAccessoryKey] as? EAAccessory {
                    self?.reportIfZebra(accessory)
                }
            }
        }
        EAAccessoryManager.shared().connectedAccessories.forEach(reportIfZebra)
        invoke("onDiscoveryDone", doneStr)
    }

    private func stopScan() {
        if let observer = scanObserver { NotificationCenter.default.removeObserver(observer) }
        scanObserver = nil
    }

    private func reportIfZebra(_ accessory: EAAccessory) {
        guard accessory.protocolStrings.contains(zebraProtocol) else { return }
        invoke("printerFound", [
            "Address": accessory.serialNumber,
            "Name": accessory.name,
            "Status": disconnectedStr,
            "IsWifi": false,
        ])
    }

    private func isZebraAccessory(_ serial: String) -> Bool {
        return EAAccessoryManager.shared().connectedAccessories.contains {
            $0.serialNumber == serial && $0.protocolStrings.contains(zebraProtocol)
        }
    }

    // MARK: Connection

    private func connect(address: String?, result: @escaping FlutterResult) {
        setStatus(connectingStr, yellow)
        forgetConnection()
        // A Wi-Fi/IP address or any serial that is not a connected Zebra accessory cannot be opened.
        guard let serial = address, isZebraAccessory(serial) else {
            queue.async { self.closeConnection() }
            setStatus(disconnectedStr, red)
            return result(true)
        }
        queue.async {
            self.closeConnection()
            let isOpen = self.openConnection(serial: serial)
            DispatchQueue.main.async {
                if isOpen {
                    self.connectedSerial = serial
                    self.observeDisconnect()
                    self.setStatus(connectedStr, green)
                } else {
                    self.setStatus(disconnectedStr, red)
                }
                result(true)
            }
        }
    }

    private func disconnect(result: @escaping FlutterResult) {
        setStatus(disconnectingStr, yellow)
        dropConnection {
            self.setStatus(disconnectedStr, red)
            result(true)
        }
    }

    private func observeDisconnect() {
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .EAAccessoryDidDisconnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let accessory = note.userInfo?[EAAccessoryKey] as? EAAccessory,
                  accessory.serialNumber == self.connectedSerial else { return }
            self.dropConnection { self.setStatus(disconnectedStr, red) }
        }
    }

    // Main thread: forget the open printer, close it on `queue`, then run `done` on the main thread.
    private func dropConnection(then done: @escaping () -> Void) {
        forgetConnection()
        queue.async {
            self.closeConnection()
            DispatchQueue.main.async(execute: done)
        }
    }

    private func forgetConnection() {
        connectedSerial = nil
        if let observer = disconnectObserver { NotificationCenter.default.removeObserver(observer) }
        disconnectObserver = nil
    }

    // MARK: Printing

    private func printData(_ text: String) {
        let bytes = text.data(using: .utf8) ?? Data()
        queue.async {
            guard self.hasConnection() else {
                return DispatchQueue.main.async { self.setStatus(disconnectedStr, red) }
            }
            DispatchQueue.main.async { self.setStatus(sendingDataStr, yellow) }
            let written = self.write(bytes)
            DispatchQueue.main.async {
                if written {
                    self.setStatus(doneStr, green)
                    self.setStatus(connectedStr, green)
                } else {
                    self.dropConnection { self.setStatus(disconnectedStr, red) }
                }
            }
        }
    }

    // MARK: Zebra SDK (on `queue` only). libZSDK_API.a has no arm64 simulator slice.

    #if !targetEnvironment(simulator)
    private func openConnection(serial: String) -> Bool {
        let candidate = MfiBtPrinterConnection(serialNumber: serial)
        guard let opened = candidate, opened.open() else { return false }
        connection = opened
        return true
    }

    private func hasConnection() -> Bool {
        return connection != nil
    }

    private func write(_ bytes: Data) -> Bool {
        var error: NSError?
        let written = connection?.write(bytes, error: &error) ?? -1
        return error == nil && written == bytes.count
    }

    private func closeConnection() {
        connection?.close()
        connection = nil
    }
    #else
    // The simulator has no printers: nothing opens, so print and connect end as "Disconnected".
    private func openConnection(serial: String) -> Bool { return false }
    private func hasConnection() -> Bool { return false }
    private func write(_ bytes: Data) -> Bool { return false }
    private func closeConnection() {}
    #endif

    // MARK: Channel (main thread only)

    private func setStatus(_ status: String, _ color: String) {
        invoke("changePrinterStatus", ["Status": status, "Color": color])
    }

    private func invoke(_ method: String, _ arguments: Any?) {
        methodChannel?.invokeMethod(method, arguments: arguments)
    }
}
