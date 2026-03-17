package com.appreveal.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

/**
 * Uses NsdManager to advertise the MCP server via mDNS/Bonjour.
 * Service type: _appreveal._tcp.
 */
internal class NsdAdvertiser(
    private val context: Context,
    private val port: Int
) {
    companion object {
        private const val TAG = "AppReveal"
        private const val SERVICE_TYPE = "_appreveal._tcp."
    }

    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null

    fun register() {
        val packageName = context.packageName
        val packageInfo = try {
            context.packageManager.getPackageInfo(packageName, 0)
        } catch (_: Exception) { null }

        val version = packageInfo?.versionName ?: "0.0.0"

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "AppReveal-$packageName"
            serviceType = SERVICE_TYPE
            setPort(this@NsdAdvertiser.port)
            setAttribute("bundleId", packageName)
            setAttribute("version", version)
            setAttribute("transport", "streamable-http")
        }

        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.i(TAG, "NSD service registered: ${info.serviceName} on port $port")
            }

            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "NSD registration failed: errorCode=$errorCode")
            }

            override fun onServiceUnregistered(info: NsdServiceInfo) {
                Log.i(TAG, "NSD service unregistered: ${info.serviceName}")
            }

            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "NSD unregistration failed: errorCode=$errorCode")
            }
        }

        registrationListener = listener
        nsdManager = (context.getSystemService(Context.NSD_SERVICE) as NsdManager).also { manager ->
            manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
        }
    }

    fun unregister() {
        registrationListener?.let { listener ->
            try {
                nsdManager?.unregisterService(listener)
            } catch (_: Exception) {
                // Already unregistered or not registered
            }
        }
        registrationListener = null
        nsdManager = null
    }
}
