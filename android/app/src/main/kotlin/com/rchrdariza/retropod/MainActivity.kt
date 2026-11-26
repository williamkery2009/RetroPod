package com.rchrdariza.retropod

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MornyeExtensions.attach(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
