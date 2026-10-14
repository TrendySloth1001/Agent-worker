package com.sparky.app

import android.app.Application

/** Installs the crash recorder as early as possible (before any Activity or Flutter engine exists). */
class SparkyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashRecorder.install(this)
    }
}
