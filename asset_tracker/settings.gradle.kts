pluginManagement {
    repositories {
        maven {
            name = "JNJ-Maven"
            url = uri("${providers.gradleProperty("artifactory_contextUrl").get()}/javz-maven-libs-release")
            credentials {
                username = providers.gradleProperty("artifactory_user").get()
                password = providers.gradleProperty("artifactory_password").get()
            }
        }
        maven {
            name = "JNJ-Google"
            url = uri("${providers.gradleProperty("artifactory_contextUrl").get()}/maven-google-com")
            credentials {
                username = providers.gradleProperty("artifactory_user").get()
                password = providers.gradleProperty("artifactory_password").get()
            }
        }
        maven {
            name = "JNJ-GradlePlugins"
            url = uri("${providers.gradleProperty("artifactory_contextUrl").get()}/plugins-gradle-org")
            credentials {
                username = providers.gradleProperty("artifactory_user").get()
                password = providers.gradleProperty("artifactory_password").get()
            }
        }
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven {
            name = "JNJ-Maven"
            url = uri("${providers.gradleProperty("artifactory_contextUrl").get()}/javz-maven-libs-release")
            credentials {
                username = providers.gradleProperty("artifactory_user").get()
                password = providers.gradleProperty("artifactory_password").get()
            }
        }
        maven {
            name = "JNJ-Google"
            url = uri("${providers.gradleProperty("artifactory_contextUrl").get()}/maven-google-com")
            credentials {
                username = providers.gradleProperty("artifactory_user").get()
                password = providers.gradleProperty("artifactory_password").get()
            }
        }
    }
}

rootProject.name = "AssetTracker"
include(":app")
