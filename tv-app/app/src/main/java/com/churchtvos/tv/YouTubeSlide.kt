package com.churchtvos.tv

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.drawable.ColorDrawable
import android.graphics.Color as AndroidColor
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Lets the remote's OK/Play button reach the YouTube player inside the WebView. */
class YouTubeController {
    var webView: WebView? = null
    fun togglePause() = webView?.evaluateJavascript("toggle()", null)
}

// YouTube refuses to play in a WebView that doesn't identify where it's embedded.
private const val EMBED_ORIGIN = "https://app.churchtvos.com"

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun YouTubeSlide(slide: Slide.YouTube, controller: YouTubeController, onEnded: () -> Unit) {
    val currentOnEnded by rememberUpdatedState(onEnded)

    SeeThroughWindow()

    // Nothing is drawn over the WebView from Compose: on this window the TV doesn't clear removed
    // Compose content, so loading/error messages live inside the page instead.
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context ->
            val main = Handler(Looper.getMainLooper())
            WebView(context).apply {
                // Keys must keep going to the player screen, not the web page.
                isFocusable = false
                isFocusableInTouchMode = false
                // Must stay transparent, or the WebView won't let its video layer show through.
                setBackgroundColor(AndroidColor.TRANSPARENT)
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.mediaPlaybackRequiresUserGesture = false
                webChromeClient = object : WebChromeClient() {
                    override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                        Log.i("YouTubeSlide", message.message())
                        return true
                    }
                }
                addJavascriptInterface(object {
                    @JavascriptInterface fun ended() = main.post { currentOnEnded() }
                }, "Android")
                loadDataWithBaseURL("$EMBED_ORIGIN/", playerHtml(slide), "text/html", "utf-8", null)
                controller.webView = this
            }
        },
    )

    DisposableEffect(controller) {
        onDispose {
            controller.webView?.destroy()
            controller.webView = null
        }
    }
}

/**
 * The WebView plays YouTube on a video layer *behind* the app window and punches a see-through
 * gap for it. The window's own backdrop must be clear too, or the video plays under it (sound, black screen).
 */
@Composable
private fun SeeThroughWindow() {
    val window = (LocalContext.current as? Activity)?.window ?: return
    DisposableEffect(window) {
        window.setBackgroundDrawable(ColorDrawable(AndroidColor.TRANSPARENT))
        onDispose { window.setBackgroundDrawable(ColorDrawable(AndroidColor.WHITE)) }
    }
}

private fun playerHtml(slide: Slide.YouTube): String {
    val live = slide.videoId == null
    // "live_stream" + channel is YouTube's embed for a channel's current live broadcast.
    val videoId = slide.videoId ?: "live_stream"
    val vars = buildJsonObject {
        put("autoplay", 1)
        put("controls", 0)
        put("rel", 0)
        put("playsinline", 1)
        put("iv_load_policy", 3)
        put("fs", 0)
        put("disablekb", 1)
        put("origin", EMBED_ORIGIN)
        if (live && slide.channelId != null) put("channel", slide.channelId)
        if (slide.start != null) put("start", slide.start)
    }
    return """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <link href="https://fonts.googleapis.com/css2?family=Lato:wght@700&display=swap" rel="stylesheet">
        <style>
          /* Black while loading (hides whatever was on screen before); see-through once the video plays. */
          html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}
          body.playing,html.playing{background:transparent}
          #player{position:fixed;top:0;left:0;width:100%;height:100%}
          #msg{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);max-width:70%;
               background:#0C426B;color:#fff;border-radius:12px;padding:20px 32px;text-align:center;
               font:700 20px/1.5 Lato,'Helvetica Neue',Arial,sans-serif;white-space:pre-line}
          #msg[hidden]{display:none}
        </style>
        </head><body><div id="player"></div><div id="msg">Loading YouTube…</div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player, started = false, live = $live;
          var msg = document.getElementById('msg');
          function see(through) {
            document.documentElement.classList.toggle('playing', through);
            document.body.classList.toggle('playing', through);
          }
          function show(text) {
            see(false);
            document.getElementById('player').style.visibility = 'hidden';  // hide YouTube's own error screen
            msg.textContent = text;
            msg.hidden = false;
          }
          function explain(code) {
            if (live) return 'Nothing is live on YouTube right now.\nPress right to skip.';
            if (code === 101 || code === 150) return "This video doesn't allow playback outside YouTube.\nPress right to skip.";
            if (code === 100) return 'This video was removed or is private.\nPress right to skip.';
            if (code === 'timeout') return 'YouTube is taking too long to start. Check the internet connection.\nPress right to skip.';
            return "YouTube couldn't play this (error " + code + '). Check the internet connection.\nPress right to skip.';
          }
          // A channel with nothing live (or a dead connection) never reports an error, so give up after a while.
          setTimeout(function () { if (!started) show(explain('timeout')); }, 20000);
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              width: '100%', height: '100%',
              videoId: ${JsonPrimitive(videoId)},
              playerVars: $vars,
              events: {
                onReady: function (e) { e.target.playVideo(); },
                onStateChange: function (e) {
                  if (e.data === YT.PlayerState.PLAYING) { started = true; msg.hidden = true; see(true); }
                  if (e.data === YT.PlayerState.ENDED) Android.ended();
                },
                onError: function (e) { console.log('YouTube error ' + e.data); show(explain(e.data)); }
              }
            });
          }
          function toggle() {
            if (!player || !player.getPlayerState) return;
            if (player.getPlayerState() === YT.PlayerState.PLAYING) player.pauseVideo(); else player.playVideo();
          }
        </script></body></html>
    """.trimIndent()
}
