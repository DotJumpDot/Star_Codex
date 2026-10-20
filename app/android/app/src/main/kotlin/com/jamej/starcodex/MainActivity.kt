package com.jamej.starcodex

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "star_codex/image_slice"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "slice" -> {
                        val path = call.argument<String>("path")
                        val maxBandHeight = call.argument<Int>("maxBandHeight") ?: 4096
                        val targetWidth = call.argument<Int>("targetWidth") ?: 0
                        if (path == null) {
                            result.error("bad_args", "path required", null)
                            return@setMethodCallHandler
                        }
                        // MethodChannel handlers run on the platform MAIN
                        // thread — decoding+compressing a multi-MB strip
                        // here froze the whole UI for hundreds of ms
                        // (2026-10-21). Do the work on a worker thread and
                        // post the (exactly-once) reply back on the looper.
                        val main = Handler(Looper.getMainLooper())
                        thread(name = "sc-image-slice") {
                            try {
                                val bands = slice(path, maxBandHeight, targetWidth)
                                main.post { result.success(bands) }
                            } catch (e: Exception) {
                                main.post { result.error("slice_failed", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Tall webtoon strips exceed Android's max GPU texture size (often
     * 8192-16384px; slow-manga serves 800x25049 pages that rendered as a
     * black void, 2026-10-21). Decodes full-width horizontal bands with
     * BitmapRegionDecoder and returns JPEG bytes per band: each band is
     * GPU-safe and the bands stack back into the original page.
     *
     * The decoder has no public close() — it is finalized (one per page,
     * short-lived; recycle() on the band bitmaps is what matters). The
     * InputStream is fully consumed at construction.
     */
    private fun slice(path: String, maxBandHeight: Int, targetWidth: Int): List<ByteArray> {
        FileInputStream(path).use { input ->
            val decoder = BitmapRegionDecoder.newInstance(input, false)
                ?: throw IllegalArgumentException("cannot decode $path")
            val w = decoder.width
            val h = decoder.height
            if (h <= maxBandHeight) return emptyList()

            // Optional downscale: sample so the band width ≈ targetWidth.
            var sample = 1
            if (targetWidth in 1 until w) {
                while (w / (sample * 2) >= targetWidth) sample *= 2
            }
            val bands = ArrayList<ByteArray>()
            var y = 0
            while (y < h) {
                val bandH = minOf(maxBandHeight, h - y)
                val opts = BitmapFactory.Options().apply {
                    inSampleSize = sample
                }
                val bmp = decoder.decodeRegion(Rect(0, y, w, y + bandH), opts)
                    ?: throw IllegalArgumentException("band decode failed at y=$y")
                val out = ByteArrayOutputStream()
                if (!bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)) {
                    throw IllegalStateException("band compress failed at y=$y")
                }
                bmp.recycle()
                bands.add(out.toByteArray())
                y += bandH
            }
            return bands
        }
    }
}
