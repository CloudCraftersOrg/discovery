pipeline {
    agent any

    stages {
        stage('Build') {
            steps {
                sh 'mvn -B package'
            }
        }
        stage('Deploy') {
            steps {
                sh '''
                    aws deploy create-deployment \
                        --application-name condor-reportes \
                        --deployment-group-name condor-reportes-prod \
                        --s3-location bucket=condor-reportes-artifacts-${AWS_ACCOUNT_ID},key=${BUILD_TAG}.zip,bundleType=zip
                '''
            }
        }
    }
}
