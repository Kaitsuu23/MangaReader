# Prevent R8 obfuscation from breaking Room / WorkManager reflection
-dontobfuscate

# WorkManager & Room
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.impl.WorkDatabase { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.startup.** { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**
-dontwarn androidx.startup.**

# Flutter Workmanager plugin
-keep class dev.fluttercommunity.workmanager.** { *; }
-dontwarn dev.fluttercommunity.workmanager.**

# ShortcutBadger & app_badge_plus
-keep class me.leolin.shortcutbadger.** { *; }
-dontwarn me.leolin.shortcutbadger.**
-keep class **.app_badge_plus.** { *; }

# Google ML Kit Text Recognition & Translation
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions*
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions*
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions*
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions*
-dontwarn com.google.mlkit.**
-dontwarn com.google_mlkit_**
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_** { *; }

# OkHttp & Okio
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Dhiksn Parsers & App
-keep class org.dhiksn.yomika.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod


