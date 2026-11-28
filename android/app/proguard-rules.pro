# JNA looks up native functions by their interface method names.
-keep interface com.rchrdariza.retropod.MornyeExtensions$Bridge { *; }
# These libraries resolve callbacks and fields from native code at runtime.
-keep class com.sun.jna.** { *; }
-keep class com.antonkarpenko.ffmpegkit.** { *; }
# JNA's desktop AWT helpers are not used on Android (upstream Android guidance).
-dontwarn java.awt.Component
-dontwarn java.awt.GraphicsEnvironment
-dontwarn java.awt.HeadlessException
-dontwarn java.awt.Window
