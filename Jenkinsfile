pipeline {
    agent any

    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        REGISTRY = 'docker.io'
        IMAGE_NAME = 'crra'
        // Images are tagged by commit SHA so a running pod is traceable to the
        // exact code that built it. ':latest' is never produced or deployed.
        IMAGE_TAG = "${env.GIT_COMMIT.take(12)}"
        DOCKER_CREDENTIALS = credentials('docker-registry-credentials')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install flake8
                    flake8 src/ tests/
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    . venv/bin/activate
                    pip install -r requirements.txt
                    pip install -e .
                    pytest --junitxml=reports/test-results.xml --cov-report=xml:reports/coverage.xml
                '''
            }
        }

        stage('Security Scan') {
            steps {
                sh '''
                    . venv/bin/activate
                    pip install bandit
                    bandit -r src/ -f json -o reports/bandit-report.json || true
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh "docker build -t ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} ."
            }
        }

        stage('Trivy Scan') {
            steps {
                sh "trivy image --exit-code 0 --severity HIGH,CRITICAL --format json -o reports/trivy-report.json ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }

        stage('Push') {
            when {
                branch 'main'
            }
            steps {
                sh "echo ${DOCKER_CREDENTIALS_PSW} | docker login ${REGISTRY} -u ${DOCKER_CREDENTIALS_USR} --password-stdin"
                sh "docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                sh 'kubectl apply -f k8s/namespace.yaml'
                sh 'kubectl apply -f k8s/configmap.yaml'
                sh 'kubectl apply -f k8s/deployment.yaml'
                sh 'kubectl apply -f k8s/service.yaml'
                // Pin the deployment to the image built from this exact commit.
                sh "kubectl set image deployment/crra crra=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n crra-dev"
                sh 'kubectl rollout status deployment/crra -n crra-dev --timeout=120s'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
            junit testResults: 'reports/test-results.xml', allowEmptyResults: true
        }
    }
}
