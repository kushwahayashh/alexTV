package com.example.alextv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.alextv.surfaceplayer.SurfaceVideoPlayerFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController
            .registry
            .registerViewFactory(
                SurfaceVideoPlayerFactory.VIEW_TYPE,
                SurfaceVideoPlayerFactory(
                    this,
                    flutterEngine.dartExecutor.binaryMessenger,
                ),
            )
    }
}
