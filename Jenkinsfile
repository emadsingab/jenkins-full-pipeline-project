pipeline {
    agent any
    tools {
        maven 'maven:3.9.12'
        jdk 'JDK21'
    }
    environment {
		SNAP_REPO = 'vprofile-snapshot'
		NEXUS_USER = credentials('nexus-login').username
		NEXUS_PASS = credentials('nexus-login').password
		RELEASE_REPO = 'vprofile-release'
		CENTRAL_REPO = 'vpro-manen-central'
		NEXUSIP = '18.116.118.118'
		NEXUSPORT = '8081'
		NEXUS_GRP_REPO = 'vpro-maven-group'
    }
    stages {
        stage('Build'){
            steps {
                sh 'mvn -s settings.xml -DskipTests install'
            }
        }
    }
}