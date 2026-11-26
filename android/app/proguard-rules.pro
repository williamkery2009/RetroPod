# Rules for the YouTube Music streaming module.
#
# NewPipeExtractor executes YouTube's player JavaScript through Rhino to
# decipher the signature and `n` parameter of stream URLs. Rhino loads classes
# reflectively, so its classes must survive R8 shrinking.

-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-dontwarn org.mozilla.javascript.tools.**

# Extractor models are deserialized/parsed reflectively in places and are
# referenced only from inside the library.
-keep class org.schabi.newpipe.extractor.** { *; }
-dontwarn org.schabi.newpipe.extractor.**

# jsoup and protobuf-lite are used by the extractor.
-dontwarn org.jsoup.**
-dontwarn com.google.protobuf.**

# The system instantiates the media session service by name.
-keep class com.rchrdariza.retropod.music.playback.YtPlaybackService { *; }

# Annotations referenced by the extractor but absent on Android.
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**

# Rhino's optional integrations with desktop APIs. Android ships none of these,
# and the extractor only drives Rhino through its direct Context API.
-dontwarn java.beans.**
-dontwarn javax.script.**
-dontwarn jdk.dynalink.**
