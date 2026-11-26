plugins {
    id("org.jetbrains.kotlin.android") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
        // NewPipeExtractor and its forked nanojson are published on JitPack
        // only. The regex keeps JitPack from being used to resolve anything
        // else. Case matters: the extractor resolves as
        // com.github.teamnewpipe, while the nanojson fork resolves as
        // com.github.TeamNewPipe.
        maven {
            url = uri("https://jitpack.io")
            content {
                includeGroupByRegex("com\\.github\\.[Tt]eam[Nn]ew[Pp]ipe")
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // file_picker 11.0.2 assumes AGP 9 always uses built-in Kotlin. Flutter
    // currently opts out of built-in Kotlin, so explicitly compile the
    // plugin's Kotlin sources until the package accounts for that setting.
    if (name == "file_picker") {
        pluginManager.apply("org.jetbrains.kotlin.android")
        extensions.configure<
            org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension
        > {
            compilerOptions {
                jvmTarget.set(
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
                )
            }
        }
    }

    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
