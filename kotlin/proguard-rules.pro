# teapod-tun2socks ProGuard / R8 rules
#
# These rules are included in the AAR and applied automatically to consuming apps.

# Keep all classes and methods of the gomobile binding.
# gomobile generates Java classes in the tun2socks.* package — they must not be obfuscated,
# because they are called via JNI by name.
-keep class tun2socks.** { *; }

# IMPORTANT: Keep gomobile's internal machinery.
# Without it the error is: failed to find method Seq.getRef
-keep class go.** { *; }

# Keep the library's Kotlin wrappers.
-keep class com.teapodstream.tun2socks.** { *; }

# gomobile uses reflection to register Go objects.
-keepclassmembers class * implements tun2socks.UIDValidatorFunc {
    public *;
}
