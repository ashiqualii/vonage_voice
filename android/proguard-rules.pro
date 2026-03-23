# ══════════════════════════════════════════════════════════════════════════
# Vonage Voice Flutter Plugin — ProGuard / R8 keep rules
# ══════════════════════════════════════════════════════════════════════════
# These rules are automatically included in consumer (app) builds via
# consumerProguardFiles in build.gradle.

# ── Vonage Client SDK ────────────────────────────────────────────────────
# The Vonage Voice SDK uses reflection, JNI, and dynamic class loading
# internally (WebRTC, okhttps, Otel). Keep all SDK classes.
-keep class com.vonage.** { *; }
-dontwarn com.vonage.**

# ── WebRTC (used by Vonage for media) ────────────────────────────────────
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# ── OkHttp / Okio (network layer used by Vonage) ────────────────────────
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**

# ── Moshi / JSON serialization (used by Vonage internally) ──────────────
-keep class com.squareup.moshi.** { *; }
-dontwarn com.squareup.moshi.**
-keep @com.squareup.moshi.JsonQualifier @interface *
-keepclassmembers class * {
    @com.squareup.moshi.FromJson *;
    @com.squareup.moshi.ToJson *;
}

# ── OpenTelemetry (Vonage ships telemetry classes) ───────────────────────
-keep class io.opentelemetry.** { *; }
-dontwarn io.opentelemetry.**

# ── Plugin classes ───────────────────────────────────────────────────────
-keep class com.iocod.vonage.vonage_voice.** { *; }

# ── Firebase Messaging ──────────────────────────────────────────────────
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.messaging.**

# ── Android Telecom framework (ConnectionService, etc.) ─────────────────
-keep class * extends android.telecom.ConnectionService { *; }
-keep class * extends android.telecom.Connection { *; }
