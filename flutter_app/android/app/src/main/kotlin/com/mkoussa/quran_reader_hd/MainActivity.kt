package com.mkoussa.quran_reader_hd

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Draw behind the status and navigation bars on every Android version, as Android 15 does by default;
        // the Flutter side keeps its content clear of them with the system insets.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
