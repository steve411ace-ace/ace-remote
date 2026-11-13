# FreeRDP JNI_OnLoad and android_jni_callback.c resolve this class, its
# no-argument constructor, and private static callbacks by their exact names.
# The file AAR supplies no consumer keep rules for these JNI entry points.
-keep class com.freerdp.freerdpcore.services.LibFreeRDP { *; }
