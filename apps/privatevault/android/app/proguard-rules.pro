# JNI finds these generated names directly; retain them through R8.
# The pinned AAR also supplies these consumer rules.
-keep class go.** { *; }
-keep class dev.privatevault.nativebridge.** { *; }
