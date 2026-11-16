package com.teapodstream.teapodstream.vpn

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import teapodcore.Vpncore
import teapodcore.XrayCallback
import teapodcore.TunValidator
import teapodcore.ProcessFinder
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class AppVpnService : VpnService() {

    private var tunFd: ParcelFileDescriptor? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val statsExecutor = Executors.newScheduledThreadPool(1)

    // Callback for the Xray status
    private val xrayCallback = object : XrayCallback {
        override fun onStatus(status: Long, message: String) {
            Log.d("AppVpnService", "Xray status ($status): $message")
        }
    }

    // Validator for tun2socks
    private val tunValidator = object : TunValidator {
        override fun onValidate(srcIP: String, srcPort: Long, dstIP: String, dstPort: Long, protocol: Long): Boolean {
            return true
        }
    }

    // Process lookup for Xray rules
    private val processFinder = object : ProcessFinder {
        override fun findProcessByConnection(network: String, srcIP: String, srcPort: Long, destIP: String, destPort: Long): Long {
            // Process lookup emulation
            return -1
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("AppVpnService", "VPN Service created. Core version: ${Vpncore.getXrayVersion()}")
        
        // Asset setup (geoip/geosite) if they are in /data/user/0/.../files/
        // Vpncore.initCoreEnv(filesDir.absolutePath, "")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val configPath = intent?.getStringExtra("CONFIG_PATH")
        val socksPort = intent?.getLongExtra("SOCKS_PORT", 10808L) ?: 10808L

        if (configPath == null) {
            return START_NOT_STICKY
        }

        executor.submit {
            try {
                startHybridVpn(configPath, socksPort)
                startStatsLogging()
            } catch (e: Exception) {
                Log.e("AppVpnService", "Failed to start", e)
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun startHybridVpn(configPath: String, socksPort: Long) {
        val configContent = java.io.File(configPath).readText()

        Log.d("AppVpnService", "Starting Xray...")
        Vpncore.startXray(configContent, xrayCallback)
        
        // Process lookup registration (optional)
        Vpncore.registerXrayProcessFinder(processFinder)

        Thread.sleep(500)

        Log.d("AppVpnService", "Establishing TUN interface...")
        val builder = Builder()
            .setSession("TeapodVPN")
            .setMtu(1500)
            .addAddress("10.0.0.2", 24)
            .addDnsServer("8.8.8.8")
            .addRoute("0.0.0.0", 0)

        tunFd = builder.establish() ?: throw IllegalStateException("Failed to establish TUN")

        val fd = tunFd!!.fd.toLong()
        Log.d("AppVpnService", "Starting tun2socks on fd $fd...")
        
        val error = Vpncore.startTun2Socks(fd, socksPort, tunValidator)
        if (error.isNotEmpty()) {
            Log.e("AppVpnService", "tun2socks error: $error")
            stopSelf()
            return
        }
        
        Log.d("AppVpnService", "Hybrid VPN is active")
    }

    private fun startStatsLogging() {
        statsExecutor.scheduleWithFixedDelay({
            if (Vpncore.isTunRunning()) {
                val upload = Vpncore.getTunUploadBytes()
                val download = Vpncore.getTunDownloadBytes()
                val cache = Vpncore.getTunCacheSize()
                Log.d("AppVpnService", "Stats: ↑$upload bytes, ↓$download bytes, cache size: $cache")
                
                // Example of getting Xray stats (if the config has a 'proxy' tag)
                // val proxyDown = Vpncore.queryXrayStats("proxy", "downlink")
            }
        }, 5, 5, TimeUnit.SECONDS)
    }

    override fun onDestroy() {
        super.onDestroy()
        statsExecutor.shutdownNow()
        executor.submit {
            Vpncore.stopTun2Socks()
            Vpncore.stopXray()
            tunFd?.close()
            tunFd = null
        }
        executor.shutdown()
    }
}
