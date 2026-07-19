package com.parkiwell.app

import android.graphics.Bitmap
import android.graphics.Matrix
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

internal class MotionPoseBridge(
    messenger: BinaryMessenger,
    private val applicationContext: Context,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var poseLandmarker: PoseLandmarker? = null
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "detect" -> detect(call, result)
            "dispose" -> dispose(result)
            else -> result.notImplemented()
        }
    }

    fun close() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        worker.execute {
            poseLandmarker?.close()
            poseLandmarker = null
        }
        worker.shutdown()
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val modelPath = call.argument<String>("modelPath")
        if (modelPath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "A pose model path is required.", null)
            return
        }
        worker.execute {
            try {
                poseLandmarker?.close()
                poseLandmarker = createLandmarker(modelPath)
                succeed(result, null)
            } catch (error: Throwable) {
                fail(result, "INITIALIZATION_FAILED", error)
            }
        }
    }

    private fun createLandmarker(modelPath: String): PoseLandmarker {
        fun options(delegate: Delegate): PoseLandmarker.PoseLandmarkerOptions {
            val modelBytes = File(modelPath).readBytes()
            val modelBuffer = ByteBuffer.allocateDirect(modelBytes.size).apply {
                put(modelBytes)
                rewind()
            }
            val baseOptions = BaseOptions.builder()
                .setModelAssetBuffer(modelBuffer)
                .setDelegate(delegate)
                .build()
            return PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumPoses(2)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .build()
        }

        return try {
            PoseLandmarker.createFromOptions(
                applicationContext,
                options(Delegate.GPU),
            )
        } catch (_: Throwable) {
            PoseLandmarker.createFromOptions(
                applicationContext,
                options(Delegate.CPU),
            )
        }
    }

    private fun detect(call: MethodCall, result: MethodChannel.Result) {
        val planes = call.argument<List<ByteArray>>("planes")
        val rowStrides = call.argument<List<Int>>("rowStrides")
        val pixelStrides = call.argument<List<Int>>("pixelStrides")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val format = call.argument<String>("format")
        val rotationDegrees = call.argument<Int>("rotationDegrees")
        val timestampMs = call.argument<Int>("timestampMs")
        if (
            planes.isNullOrEmpty() ||
            rowStrides == null ||
            pixelStrides == null ||
            width == null ||
            height == null ||
            format == null ||
            rotationDegrees == null ||
            timestampMs == null
        ) {
            result.error("INVALID_ARGUMENTS", "Incomplete camera frame metadata.", null)
            return
        }

        worker.execute {
            try {
                val landmarker = poseLandmarker
                    ?: throw IllegalStateException("Pose runtime is not initialized.")
                val source = when (format) {
                    "yuv420" -> yuv420ToBitmap(
                        planes,
                        rowStrides,
                        pixelStrides,
                        width,
                        height,
                    )
                    "nv21" -> nv21ToBitmap(planes.first(), width, height)
                    else -> throw IllegalArgumentException(
                        "Unsupported Android camera format: $format",
                    )
                }
                val rotated = rotateBitmap(source, rotationDegrees)
                val started = System.nanoTime()
                val detection = landmarker.detect(BitmapImageBuilder(rotated).build())
                val inferenceMs = (System.nanoTime() - started) / 1_000_000.0
                val response = mutableMapOf<String, Any?>(
                    "timestampMs" to timestampMs,
                    "inferenceMs" to inferenceMs,
                    "poseCount" to detection.landmarks().size,
                    "landmarks" to null,
                    "worldLandmarks" to null,
                )
                if (detection.landmarks().isNotEmpty()) {
                    val landmarks = detection.landmarks().first()
                    val world = detection.worldLandmarks().firstOrNull()
                    response["landmarks"] = landmarks.map { landmark ->
                        mapOf(
                            "x" to landmark.x().toDouble(),
                            "y" to landmark.y().toDouble(),
                            "z" to landmark.z().toDouble(),
                            "visibility" to landmark.visibility().orElse(0f).toDouble(),
                            "presence" to landmark.presence().orElse(0f).toDouble(),
                        )
                    }
                    response["worldLandmarks"] = world?.mapIndexed { index, landmark ->
                        mapOf(
                            "x" to landmark.x().toDouble(),
                            "y" to landmark.y().toDouble(),
                            "z" to landmark.z().toDouble(),
                            "visibility" to landmarks[index]
                                .visibility()
                                .orElse(0f)
                                .toDouble(),
                            "presence" to landmarks[index]
                                .presence()
                                .orElse(0f)
                                .toDouble(),
                        )
                    }
                }
                if (rotated !== source) {
                    source.recycle()
                }
                rotated.recycle()
                succeed(result, response)
            } catch (error: Throwable) {
                fail(result, "DETECTION_FAILED", error)
            }
        }
    }

    private fun dispose(result: MethodChannel.Result) {
        worker.execute {
            poseLandmarker?.close()
            poseLandmarker = null
            succeed(result, null)
        }
    }

    private fun yuv420ToBitmap(
        planes: List<ByteArray>,
        rowStrides: List<Int>,
        pixelStrides: List<Int>,
        width: Int,
        height: Int,
    ): Bitmap {
        require(planes.size >= 3) { "YUV420 frames require three planes." }
        val output = IntArray(width * height)
        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val yRowStride = rowStrides[0]
        val uRowStride = rowStrides[1]
        val vRowStride = rowStrides[2]
        val yPixelStride = pixelStrides[0]
        val uPixelStride = pixelStrides[1]
        val vPixelStride = pixelStrides[2]

        for (row in 0 until height) {
            val chromaRow = row / 2
            for (column in 0 until width) {
                val chromaColumn = column / 2
                val yIndex = row * yRowStride + column * yPixelStride
                val uIndex = chromaRow * uRowStride + chromaColumn * uPixelStride
                val vIndex = chromaRow * vRowStride + chromaColumn * vPixelStride
                output[row * width + column] = yuvToArgb(
                    yPlane[yIndex].toInt() and 0xff,
                    uPlane[uIndex].toInt() and 0xff,
                    vPlane[vIndex].toInt() and 0xff,
                )
            }
        }
        return Bitmap.createBitmap(output, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun nv21ToBitmap(bytes: ByteArray, width: Int, height: Int): Bitmap {
        require(bytes.size >= width * height * 3 / 2) { "NV21 frame is truncated." }
        val output = IntArray(width * height)
        val ySize = width * height
        for (row in 0 until height) {
            for (column in 0 until width) {
                val y = bytes[row * width + column].toInt() and 0xff
                val chroma = ySize + (row / 2) * width + (column / 2) * 2
                val v = bytes[chroma].toInt() and 0xff
                val u = bytes[chroma + 1].toInt() and 0xff
                output[row * width + column] = yuvToArgb(y, u, v)
            }
        }
        return Bitmap.createBitmap(output, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun yuvToArgb(y: Int, uByte: Int, vByte: Int): Int {
        val u = uByte - 128
        val v = vByte - 128
        val red = clamp(y + 1.402 * v)
        val green = clamp(y - 0.344136 * u - 0.714136 * v)
        val blue = clamp(y + 1.772 * u)
        return (0xff shl 24) or (red shl 16) or (green shl 8) or blue
    }

    private fun clamp(value: Double): Int = max(0, min(255, value.toInt()))

    private fun rotateBitmap(source: Bitmap, degrees: Int): Bitmap {
        val normalized = ((degrees % 360) + 360) % 360
        if (normalized == 0) return source
        val matrix = Matrix().apply { postRotate(normalized.toFloat()) }
        return Bitmap.createBitmap(
            source,
            0,
            0,
            source.width,
            source.height,
            matrix,
            true,
        )
    }

    private fun succeed(result: MethodChannel.Result, value: Any?) {
        mainHandler.post {
            if (!closed) result.success(value)
        }
    }

    private fun fail(
        result: MethodChannel.Result,
        code: String,
        error: Throwable,
    ) {
        mainHandler.post {
            if (!closed) {
                result.error(code, error.message ?: "Motion pose processing failed.", null)
            }
        }
    }

    companion object {
        private const val CHANNEL_NAME = "com.parkiwell.app/motion_pose"
    }
}
