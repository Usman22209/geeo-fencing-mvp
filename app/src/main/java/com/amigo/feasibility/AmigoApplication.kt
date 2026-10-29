package com.amigo.feasibility

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.notification.NotificationSender
import java.util.concurrent.atomic.AtomicInteger

class AmigoApplication : Application(), Application.ActivityLifecycleCallbacks {

    companion object {
        var isColdStart: Boolean = true
            private set

        fun markColdStartHandled() {
            isColdStart = false
        }
    }

    private val runningActivities = AtomicInteger(0)

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(this)
        Config.init(this)
        Logger.init(this)
        NotificationSender.createChannels(this)
    }

    override fun onActivityStarted(activity: Activity) {
        if (runningActivities.incrementAndGet() > 0) {
            Logger.currentAppState = "foreground"
        }
    }

    override fun onActivityStopped(activity: Activity) {
        if (runningActivities.decrementAndGet() <= 0) {
            Logger.currentAppState = "background"
        }
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
