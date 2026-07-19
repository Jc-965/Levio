package com.parkiwell.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private var motionPoseBridge: MotionPoseBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        motionPoseBridge = MotionPoseBridge(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        motionPoseBridge?.close()
        motionPoseBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
