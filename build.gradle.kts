plugins {
    id("com.android.application") version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}
																																																																																																																																																																																				tasks.register<Exec>("startApi") { workingDir = rootProject.projectDir; commandLine("cmd", "/c", "start", "\"\"", "cmd", "/k", "node", "service") }
