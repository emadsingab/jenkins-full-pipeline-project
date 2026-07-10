pipeline {
    agent any

    tools {
        maven 'maven:3.9.12'
        jdk 'JDK21'
    }

    environment {
        SNAP_REPO      = 'vprofile-snapshot'
        RELEASE_REPO   = 'vprofile-release'
        CENTRAL_REPO   = 'vpro-maven-central'
        NEXUSIP        = '172.31.14.229'
        NEXUSPORT      = '8081'
        NEXUS_GRP_REPO = 'vpro-maven-group'
    }

    stages {
        stage('Build') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'nexus-login',
                        usernameVariable: 'NEXUS_USER',
                        passwordVariable: 'NEXUS_PASS'
                    )
                ]) {
                    sh 'mvn -s settings.xml -DskipTests install'
                }
                post {
                    success {
                        echo 'Now archiving the artifacts'
                        archiveArtifacts artifacts: '**/*.war'
                    }
                }
                    
            }
        }
        stage ("Test"){
            steps{
                sh 'mvn -s settings.xml test'
            }
        }
        stage ("Checkstyle Analysis"){
            steps{
                sh 'mvn -s settings.xml checkstyle:checkstyle'
            }
        }
    }

}
