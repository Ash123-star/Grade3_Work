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
    // AGP generates unit-test resource paths relative to each plugin's source.
    // Windows cannot relativize a Pub cache on C: against build output on D:.
    // Keep cross-drive output beside the plugin, isolated for this application.
    val sameDrive = projectDir.toPath().root == newBuildDir.asFile.toPath().root
    val projectBuildKey = rootProject.projectDir.absolutePath.hashCode().toUInt().toString(16)
    val newSubprojectBuildDir: Directory = if (sameDrive) {
        newBuildDir.dir(project.name)
    } else {
        layout.projectDirectory.dir("build/pandora-$projectBuildKey/${project.name}")
    }
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
