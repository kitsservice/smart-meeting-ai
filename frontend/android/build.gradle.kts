allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}





subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
            apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
            
            val currentArgs = freeCompilerArgs.get()
            val newArgs = mutableListOf<String>()
            var skipNext = false
            for (i in currentArgs.indices) {
                if (skipNext) {
                    skipNext = false
                    continue
                }
                if (currentArgs[i] == "-language-version" || currentArgs[i] == "-api-version") {
                    skipNext = true
                    continue
                }
                newArgs.add(currentArgs[i])
            }
            freeCompilerArgs.set(newArgs)
        }
    }
}
