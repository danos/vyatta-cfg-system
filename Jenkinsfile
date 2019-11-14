#!groovy

pipeline {
    agent any

    options {
        ansiColor('xterm')
        timestamps()
    }

    stages {
        stage('DRAM') {
            steps {
                sh "dram --username jenkins -d yang"
            }
        }
        stage('Perlcritic') {
            steps {
                sh script: "perlcritic --quiet --severity 5 . 2>&1 | tee perlcritic.txt", returnStatus: true
            }
        }
    }

    post {
        always {
            recordIssues tool: perlCritic(pattern: 'perlcritic.txt'),
                qualityGates: [[type: 'TOTAL', threshold: 1, unstable: true]]

            // Do any clean up for DRAM?

            deleteDir()
        }
    }

}
