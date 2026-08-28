package com.agbc.scanagbc

import android.content.pm.ActivityInfo
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    window.setSoftInputMode(
      WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN or
        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
    )
  }
}
