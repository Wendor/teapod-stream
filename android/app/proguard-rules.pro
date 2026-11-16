# ProGuard / R8 rules for TeapodStream
# Fix for: Abort message: 'failed to find method Seq.getRef'

# Keep GoMobile internal classes
-keep class go.** { *; }

# Keep teapod-tun2socks library classes
-keep class tun2socks.** { *; }
-keep class com.teapodstream.tun2socks.** { *; }

# Keep other JNI boundaries if necessary
-keep class com.teapodstream.teapodstream.** { *; }

# Rust core (xray-rust-mobile): JNI finds classes and callbacks by name.
-keep class org.xrayrust.mobile.** { *; }
