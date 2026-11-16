package com.amigorn

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.facebook.react.PackageList
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.ReactNativeHost
import com.facebook.react.ReactPackage
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.load
import com.facebook.react.defaults.DefaultReactHost.getDefaultReactHost
import com.facebook.react.defaults.DefaultReactNativeHost
import com.facebook.react.soloader.OpenSourceMergedSoMapping
import com.facebook.soloader.SoLoader
import com.amigo.feasibility.bridge.AmigoProximityPackage
import com.amigo.feasibility.Config
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.notification.NotificationSender

class MainApplication : Application(), ReactApplication, Application.ActivityLifecycleCallbacks {

  companion object {
      var isColdStart: Boolean = true
          private set

      fun markColdStartHandled() {
          isColdStart = false
      }
  }

  private val runningActivities = java.util.concurrent.atomic.AtomicInteger(0)

  override val reactNativeHost: ReactNativeHost =
      object : DefaultReactNativeHost(this) {
        override fun getPackages(): List<ReactPackage> =
            PackageList(this).packages.apply {
              add(AmigoProximityPackage())
            }

        override fun getJSMainModuleName(): String = "index"

        override fun getUseDeveloperSupport(): Boolean = BuildConfig.DEBUG

        override val isNewArchEnabled: Boolean = BuildConfig.IS_NEW_ARCHITECTURE_ENABLED
        override val isHermesEnabled: Boolean = BuildConfig.IS_HERMES_ENABLED
      }

  override val reactHost: ReactHost
    get() = getDefaultReactHost(applicationContext, reactNativeHost)

  override fun onCreate() {
    super.onCreate()
    SoLoader.init(this, OpenSourceMergedSoMapping)

    // Initialize AMIGO native engine
    Config.init(this)
    Logger.init(this)
    NotificationSender.createChannels(this)
    registerActivityLifecycleCallbacks(this)

    if (BuildConfig.IS_NEW_ARCHITECTURE_ENABLED) {
      load()
    }
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
