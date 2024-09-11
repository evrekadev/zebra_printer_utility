
package com.rubdev.zebrautil;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothClass;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.os.Handler;

import com.zebra.sdk.printer.discovery.DeviceFilter;
import com.zebra.sdk.printer.discovery.DiscoveredPrinterBluetooth;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public class BluetoothDiscoverer {
    private final Context mContext;
    private final DiscoveryHandlerCustom mDiscoveryHandler;
    BluetoothDiscoverer.BtReceiver btReceiver;
    BluetoothDiscoverer.BtRadioMonitor btMonitor;
    private final DeviceFilter deviceFilter;
    private static BluetoothDiscoverer bluetoothDiscoverer;

    private BluetoothDiscoverer(Context context, DiscoveryHandlerCustom handler, DeviceFilter filter) {
        this.mContext = context.getApplicationContext();
        this.deviceFilter = filter;
        this.mDiscoveryHandler = handler;
    }

    public static void findPrinters(Context context, DiscoveryHandlerCustom handler, DeviceFilter filter) {
        BluetoothAdapter var3 = BluetoothAdapter.getDefaultAdapter();
        if (var3 == null) {
            handler.discoveryError("No bluetooth radio found");
        } else if (!var3.isEnabled()) {
            handler.discoveryError("Bluetooth radio is currently disabled");
        } else {
            if (var3.isDiscovering()) {
                var3.cancelDiscovery();
            }

            if (bluetoothDiscoverer == null) {
                bluetoothDiscoverer = new BluetoothDiscoverer(context.getApplicationContext(), handler, filter);
            }
            bluetoothDiscoverer.doBluetoothDisco();
        }

    }

    public static void findPrinters(Context context, DiscoveryHandlerCustom handler)  {
        DeviceFilter filter = value -> true;
        findPrinters(context, handler, filter);
    }

    private void unregisterTopLevelReceivers(Context var1) {
        if (this.btReceiver != null) {
            var1.unregisterReceiver(this.btReceiver);
        }

        if (this.btMonitor != null) {
            var1.unregisterReceiver(this.btMonitor);
        }
    }

    public static void stopBluetoothDiscovery() {
        if (bluetoothDiscoverer != null) {
            bluetoothDiscoverer.unregisterTopLevelReceivers(bluetoothDiscoverer.mContext);
            bluetoothDiscoverer = null;
        }
    }

    private void doBluetoothDisco() {
        this.btReceiver = new BluetoothDiscoverer.BtReceiver();
        this.btMonitor = new BluetoothDiscoverer.BtRadioMonitor();
        IntentFilter var1 = new IntentFilter(BluetoothDevice.ACTION_FOUND);
        IntentFilter var2 = new IntentFilter(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
        IntentFilter var3 = new IntentFilter(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED);

        this.mContext.registerReceiver(this.btReceiver, var1);
        this.mContext.registerReceiver(this.btReceiver, var2);
        this.mContext.registerReceiver(this.btMonitor, var3);
        BluetoothAdapter.getDefaultAdapter().startDiscovery();

    }

    private class BtRadioMonitor extends BroadcastReceiver {
        private BtRadioMonitor() {
        }

        public void onReceive(Context var1, Intent var2) {
            String var3 = var2.getAction();
            if (BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED.equals(var3)) {
                Bundle var4 = var2.getExtras();
                if(var4 == null){
                    return;
                }
                int var5 = var4.getInt(BluetoothAdapter.EXTRA_STATE);
                if (var5 == 10) {
                    BluetoothDiscoverer.this.mDiscoveryHandler.discoveryFinished();
                }
            }

        }
    }

    private class BtReceiver extends BroadcastReceiver {
        private static final int BLUETOOTH_PRINTER_CLASS = 1664;
        private static final long DISCOVERY_INTERVAL = 10000;
        private static final long DEVICE_TIMEOUT = 25000;
        private final Map<BluetoothDevice,Long> foundDevices;

        private BtReceiver() {
            this.foundDevices = new HashMap<>();
        }

        public void onReceive(Context var1, Intent intent) {
            String action = intent.getAction();
            if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                this.processFoundPrinter(intent);
            } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                checkForMissingDevices();
                BluetoothDiscoverer.this.mDiscoveryHandler.discoveryFinished();
                new Handler().postDelayed(() -> BluetoothAdapter.getDefaultAdapter().startDiscovery(), DISCOVERY_INTERVAL);
            }

        }

        private void checkForMissingDevices() {
            long currentTime = System.currentTimeMillis();
            Iterator<Map.Entry<BluetoothDevice, Long>> iterator = foundDevices.entrySet().iterator();
            while (iterator.hasNext()) {
                Map.Entry<BluetoothDevice,Long> entry = iterator.next();
                long lastSeenTime = entry.getValue();
                BluetoothDevice lastSeenDevice = entry.getKey();
               if (currentTime - lastSeenTime > DEVICE_TIMEOUT) {
                   mDiscoveryHandler.printerOutOfRange(
                            new DiscoveredPrinterBluetooth(
                                    lastSeenDevice.getAddress(),
                                    lastSeenDevice.getName()));
                    iterator.remove();
                }
            }
        }

        private void processFoundPrinter(Intent var1) {
            BluetoothDevice var2 = (BluetoothDevice)var1.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
            if(var2 == null){
                return;
            }
            if (this.isPrinterClass(var2) && BluetoothDiscoverer.this.deviceFilter != null && BluetoothDiscoverer.this.deviceFilter.shouldAddPrinter(var2)) {
                BluetoothDiscoverer.this.mDiscoveryHandler.foundPrinter(new DiscoveredPrinterBluetooth(var2.getAddress(), var2.getName()));
                Long foundAt = System.currentTimeMillis();
                this.foundDevices.put(var2, foundAt);
            }

        }

        private boolean isPrinterClass(BluetoothDevice var1) {
            BluetoothClass var2 = var1.getBluetoothClass();
            if (var2 != null) {
                return var2.getDeviceClass() == BLUETOOTH_PRINTER_CLASS;
            } else {
                return false;
            }
        }
    }
}
