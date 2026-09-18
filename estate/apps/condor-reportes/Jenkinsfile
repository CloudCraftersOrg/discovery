pipeline {
    agent any

    stages {
        stage('Build') {
            steps {
                sh 'mvn -B -DskipTests package'
            }
        }
        stage('Test') {
            steps {
                sh 'mvn -B test'
            }
        }
        stage('Deploy') {
            steps {
                sh '''
                    sudo cp target/condor-reportes.jar /opt/condor-reportes/condor-reportes.jar
                    sudo systemctl restart condor-reportes
                '''
            }
        }
    }
}
