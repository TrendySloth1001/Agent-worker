# flutter_local_notifications serializes scheduled notifications with Gson and
# looks up its classes reflectively; keep them intact under R8.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# MainActivity is referenced from the manifest; FileProvider from the manifest too.
-keep class com.sparky.app.MainActivity { *; }
-keep class androidx.core.content.FileProvider { *; }

# "Continue with Google" (Credential Manager): the Play Services provider is
# loaded reflectively by androidx.credentials, and Sign in with Google parses
# its credential bundle; keep both under R8.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
