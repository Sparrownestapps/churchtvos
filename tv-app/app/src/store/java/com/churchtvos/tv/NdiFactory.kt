package com.churchtvos.tv

import android.content.Context

/** The store build contains no NDI code or libraries: there is no receiver. NDI items are skipped or show their fallback message. */
@Suppress("UNUSED_PARAMETER")
fun createNdiReceiver(context: Context): NdiReceiver? = null
