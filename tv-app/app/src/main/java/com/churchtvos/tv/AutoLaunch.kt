package com.churchtvos.tv

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Brings Church TV OS to the front when the TV boots or wakes from standby,
 * so volunteers never have to find the app. Only for TVs that are paired to a room.
 */
object AutoLaunch {
    fun isEnabled(context: Context): Boolean = DeviceStore(context).let { it.isPaired && it.autoLaunch }

    fun start(context: Context) {
        if (!isEnabled(context)) return
        val intent = Intent(context, WakeWatcherService::class.java)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
    }

    /** Turns auto-launch on or off right away (starts or stops the background watcher). */
    fun setEnabled(context: Context, enabled: Boolean) {
        DeviceStore(context).also { it.autoLaunch = enabled; it.autoLaunchAsked = true }
        if (enabled) start(context) else context.stopService(Intent(context, WakeWatcherService::class.java))
    }

    fun bringToFront(context: Context) {
        if (!isEnabled(context)) return
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
        )
    }
}

/** Fires after a reboot or an app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AutoLaunch.start(context)
        AutoLaunch.bringToFront(context)
    }
}

/**
 * Screen-on can only be heard by a running component, so this small service stays alive
 * in the background and relaunches the app each time the TV is switched on.
 */
class WakeWatcherService : Service() {
    private val main = Handler(Looper.getMainLooper())

    private val screenOn = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            // Let the Fire TV home screen finish appearing first, then come in on top of it.
            main.postDelayed({ AutoLaunch.bringToFront(this@WakeWatcherService) }, 2_500)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("auto_launch", "Auto-launch", NotificationManager.IMPORTANCE_MIN))
        }
        val notification = NotificationCompat.Builder(this, "auto_launch")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Church TV OS opens when this TV turns on")
            .build()
        ServiceCompat.startForeground(this, 1, notification, if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0)
        registerReceiver(screenOn, IntentFilter(Intent.ACTION_SCREEN_ON))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!AutoLaunch.isEnabled(this)) stopSelf()
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterReceiver(screenOn)
        main.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
