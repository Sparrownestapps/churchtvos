package com.churchtvos.tv

/** Built-in sample content for app-store reviewers and first-time visitors. Needs no account and no network. */
object Demo {
    const val KIDS = "kids"
    const val SIGNAGE = "signage"

    fun slides(which: String): List<Slide> = when (which) {
        SIGNAGE -> listOf(
            Slide.Bundled(R.drawable.demo_welcome, 6),
            Slide.Bundled(R.drawable.demo_events, 6),
            Slide.Bundled(R.drawable.demo_info, 6),
        )
        else -> listOf(
            Slide.Countdown("Service starts in", CountdownSpec(seconds = 10), null),
            Slide.Lyric("Sample song", "Verse 1\nSample lyrics appear\nlarge and centred", 1, 2),
            Slide.Lyric("Sample song", "Chorus\nOne slide per section,\nadvance with Right", 2, 2),
            Slide.Bundled(R.drawable.demo_welcome, 6),
        )
    }
}
