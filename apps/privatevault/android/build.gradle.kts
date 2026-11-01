allprojects { repositories { google(); mavenCentral() } }
val pvBuildDir = rootProject.layout.projectDirectory.dir("../build/android")
rootProject.layout.buildDirectory.set(pvBuildDir)
subprojects { layout.buildDirectory.set(pvBuildDir.dir(name)) }
tasks.register<Delete>("clean") { delete(rootProject.layout.buildDirectory) }
