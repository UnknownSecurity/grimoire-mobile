package com.unknownsecurity.grimoireexodus.mobile.ruffle

import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView

private const val AQW_ASPECT_RATIO = 960f / 550f

/** Keeps Ruffle and AQW on the original 960x550 logical coordinate plane. */
@Composable
fun RuffleGameSurface(
    transport: RuffleGameTransport,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(
        modifier = modifier.background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        val availableRatio = if (maxHeight.value > 0f) maxWidth / maxHeight else AQW_ASPECT_RATIO
        val gameModifier = if (availableRatio > AQW_ASPECT_RATIO) {
            Modifier
                .fillMaxHeight()
                .aspectRatio(AQW_ASPECT_RATIO, matchHeightConstraintsFirst = true)
        } else {
            Modifier
                .fillMaxWidth()
                .aspectRatio(AQW_ASPECT_RATIO)
        }
        Box(modifier = gameModifier, contentAlignment = Alignment.Center) {
            AndroidView(
                factory = { context ->
                    WebView(context).also(transport::attach)
                },
                update = { view -> transport.attach(view) },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }

    DisposableEffect(transport) {
        onDispose { transport.detach() }
    }
}
