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
    // AGP 9: CommonExtension unifica app/library; compileSdk é var? —
    // define 36 em qualquer plugin compilado contra SDK mais antigo
    // (ex: iris_method_channel contra android-31). Não mexe em
    // minSdk/targetSdk nem no módulo :app (que já usa 37 via app).
    afterEvaluate {
        val ext = project.extensions.findByName("android")
            as? com.android.build.api.dsl.CommonExtension
        if (ext != null) {
            val current = ext.compileSdk
            if (current == null || current < 36) {
                ext.compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
