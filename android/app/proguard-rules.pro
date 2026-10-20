# shared_preferences_android 2.5 uses JNI to look up suspend methods by their
# original JVM signatures. Renaming Continuation changes those signatures and
# causes SharedPreferences.getInstance() to fail before Flutter's first frame.
-keep class kotlin.coroutines.Continuation { *; }

# JNI also resolves Kotlin coroutine results and generated method parameter
# types by name. Keep these to avoid subsequent failures after getAll succeeds.
-keep class kotlin.coroutines.intrinsics.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.enums.EnumEntries { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
