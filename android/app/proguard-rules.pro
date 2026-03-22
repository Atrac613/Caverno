# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.plugins.** { *; }

# Easy Localization
-keep class com.easy_localization.** { *; }

# Service/Entity classes if used in JNI (e.g. for notifications or native communication)
-keep class com.noguwo.apps.caverno.** { *; }
-keepclassmembers class com.noguwo.apps.caverno.** { *; }

# General ProGuard rules
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.gms.**
-dontwarn androidx.**
