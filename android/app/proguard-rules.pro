# Flutter Engine Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep all plugin classes and generated registries
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Ignore warnings for missing third-party references during R8 optimization
-dontwarn **
-dontnote **
-ignorewarnings

# Keep Gson / JSON model field names
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Supabase & Networking
-keep class com.supabase.** { *; }
-keep class io.supabase.** { *; }

# Firebase & Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# OneSignal & Notifications
-keep class com.onesignal.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# PDF & Printing
-keep class net.nfdk.** { *; }
-keep class com.printing.** { *; }
