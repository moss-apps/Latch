# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# pointycastle (crypto)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Autofill service
-keep class com.mossapps.locker.AutofillService { *; }
-keep class com.mossapps.locker.AutofillSelectionActivity { *; }
