package com.aether

class AetherEngine {
    private var nativePtr: Long = 0

    init {
        nativePtr = nativeInit()
    }

    fun evaluateJS(script: String) {
        nativeEvaluateJS(nativePtr, script)
    }

    fun runEventLoop() {
        nativeRunEventLoop(nativePtr)
    }

    private external fun nativeInit(): Long
    private external fun nativeEvaluateJS(ptr: Long, script: String)
    private external fun nativeRunEventLoop(ptr: Long)

    companion object {
        init {
            System.loadLibrary("aether")
        }
    }
}
