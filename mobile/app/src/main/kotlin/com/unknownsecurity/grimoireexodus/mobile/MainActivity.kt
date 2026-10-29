package com.unknownsecurity.grimoireexodus.mobile

import android.content.pm.ActivityInfo
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.unknownsecurity.grimoireexodus.designsystem.GrimoireExodusTheme
import com.unknownsecurity.grimoireexodus.mobile.ui.GrimoireExodusApp
import com.unknownsecurity.grimoireexodus.mobile.ruffle.RuffleGameTransport

class MainActivity : ComponentActivity() {
    private lateinit var transport: RuffleGameTransport

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        enableEdgeToEdge()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        enterImmersiveMode()
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
        transport = RuffleGameTransport(applicationContext)
        setContent {
            GrimoireExodusTheme {
                GrimoireExodusApp(transport = transport)
            }
        }
    }

    override fun onDestroy() {
        if (::transport.isInitialized) {
            transport.close()
        }
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enterImmersiveMode()
        }
    }

    private fun enterImmersiveMode() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }
}
