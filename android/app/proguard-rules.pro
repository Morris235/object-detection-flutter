# TensorFlow Lite GPU Delegate 관련 규칙
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

# TensorFlow Lite Select TF Ops 관련 규칙 (필요한 경우)
-keep class org.tensorflow.lite.selecttfops.** { *; }
-dontwarn org.tensorflow.lite.selecttfops.**

# 기본적으로 필요한 TensorFlow Lite 규칙
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Flutter와 관련된 기본 규칙
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Android 기본 ProGuard 규칙 유지
-keep public class * extends android.app.Application
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.app.Service
-keep public class * extends android.app.Activity

-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.nnapi.** { *; }
-dontwarn org.tensorflow.**