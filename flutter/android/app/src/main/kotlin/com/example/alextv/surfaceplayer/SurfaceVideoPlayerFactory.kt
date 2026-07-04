package com.example.alextv.surfaceplayer

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class SurfaceVideoPlayerFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val VIEW_TYPE = "com.example.alextv/surface_video_player"
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = (args as? Map<String, Any>) ?: emptyMap()
        val channelName = "$VIEW_TYPE/$viewId"
        val methodChannel = MethodChannel(messenger, channelName)
        return SurfaceVideoPlayer(context, params, methodChannel)
    }
}
