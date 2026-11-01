#!/bin/zsh
set -eu
source "${0:A:h}/w01_android_env.sh"
pv_kotlin_lib="$GRADLE_HOME/lib"
pv_kotlin_src="$pv_root/apps/privatevault/android/app/src/main/kotlin/dev/privatevault/w01"
print 'Host-only contract diagnostic: Gradle-bundled Kotlin 2.2.21; Android Kotlin remains pinned to 2.4.0.'
java -cp "$pv_kotlin_lib/*" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
  -no-stdlib -no-reflect -jvm-target 17 \
  -classpath "$pv_kotlin_lib/kotlin-stdlib-2.2.21.jar" \
  -d "$pv_root/.local/w01-a/contracts.jar" \
  "$pv_kotlin_src/CoreReplyGate.kt" "$pv_kotlin_src/CoreEndpoint.kt" "$pv_kotlin_src/CoreTokenProof.kt" \
  "$pv_root/tools/kotlin/CheckW01Contracts.kt"
java -cp "$pv_root/.local/w01-a/contracts.jar:$pv_kotlin_lib/kotlin-stdlib-2.2.21.jar" dev.privatevault.w01.CheckW01ContractsKt
