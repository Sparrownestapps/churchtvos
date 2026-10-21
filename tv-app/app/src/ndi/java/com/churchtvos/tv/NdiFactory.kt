package com.churchtvos.tv

import android.content.Context
import com.churchtvos.ndi.NdiNative

/** The experimental build: a real receiver, or null if the native libraries did not load (the slide then follows its fallback). */
fun createNdiReceiver(context: Context): NdiReceiver? =
    if (NdiNative.loaded) NdiNativeReceiver(context.applicationContext) else null
