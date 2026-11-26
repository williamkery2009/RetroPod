package com.rchrdariza.retropod

import com.rchrdariza.retropod.music.bridge.YtMusicBridge
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts the Flutter engine and registers the native YouTube Music bridge.
 *
 * Extends [AudioServiceActivity] (the activity `audio_service` uses instead of
 * the default `FlutterActivity`) so the local library keeps using its existing
 * audio service while the streaming module registers its own platform
 * channels.
 */
class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        YtMusicBridge.attach(flutterEngine, this)
    }
}
