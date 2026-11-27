package com.rchrdariza.retropod

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun onDestroy() {
        YoutubeAccount.closeLogin()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        YoutubeAccount.attach(this, flutterEngine.dartExecutor.binaryMessenger)
        MornyeExtensions.attach(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
