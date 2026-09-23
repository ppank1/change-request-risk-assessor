pipeline {
    agent any

    triggers {
        pollSCM('H/2 * * * *')
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        REGISTRY = 'docker.io'
        IMAGE_NAME = 'crra'
        // Images are tagged by commit SHA so a running pod is traceable to the
        // exact code that built it. ':latest' is never produced or deployed.
        IMAGE_TAG = "${env.GIT_COMMIT.take(12)}"
        // Docker Hub credential; its username is also the image namespace,
        // so the pushed image is docker.io/<user>/crra:<sha>.
        DOCKER_CREDENTIALS = credentials('docker-registry-credentials')
        TF_DIR = 'terraform/environments/dev'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = '0'
        AWS_REGION = 'us-west-2'
        // AWS access comes from the host's instance profile (crra-jenkins-role):
        // read state + lock + describe for plan, SSM sessions for Ansible.
        // No access keys are stored anywhere in Jenkins.
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'mkdir -p reports'
            }
        }

        // ---------------- Application ----------------

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

        // ---------------- Infrastructure as code ----------------

        stage('Terraform Validate') {
            steps {
                // fmt -check fails on any unformatted file; validate runs
                // without a backend so it needs no AWS access or state lock.
                sh '''
                    terraform fmt -check -recursive -diff terraform/
                    for dir in terraform/bootstrap ${TF_DIR}; do
                        echo "== validate ${dir}"
                        terraform -chdir=${dir} init -backend=false -input=false >/dev/null
                        terraform -chdir=${dir} validate
                    done
                '''
            }
        }

        stage('IaC Security Scan') {
            steps {
                // tfsec scans a root module and everything it calls, so both
                // roots are scanned. Findings fail the stage; accepted risks
                // are annotated in-code with a tfsec:ignore and a reason.
                sh '''
                    tfsec --version
                    # --no-colour: the Jenkins console has no ANSI renderer, so
                    # colour codes would print as literal escape sequences.
                    # JSON artefacts first (soft-fail so they exist even when
                    # findings then fail the console run below).
                    tfsec ${TF_DIR} --no-colour --tfvars-file ${TF_DIR}/dev.tfvars --soft-fail --format json --out reports/tfsec-dev.json
                    tfsec terraform/bootstrap --no-colour --soft-fail --format json --out reports/tfsec-bootstrap.json
                    tfsec ${TF_DIR} --no-colour --tfvars-file ${TF_DIR}/dev.tfvars
                    tfsec terraform/bootstrap --no-colour
                '''
            }
        }

        stage('Ansible Lint') {
            steps {
                sh 'cd ansible && ansible-lint --version && ansible-lint --profile production'
            }
        }

        stage('Terraform Plan') {
            steps {
                // Plan against dev is archived as an artefact for review; apply
                // stays a human action. The lock is taken and released like any
                // other operator, so a concurrent apply blocks this stage.
                sh '''#!/usr/bin/env bash
                    set -euo pipefail
                    terraform -chdir=${TF_DIR} init -input=false
                    terraform -chdir=${TF_DIR} plan -var-file=dev.tfvars -lock-timeout=60s \
                        -out=dev.tfplan -no-color | tee reports/terraform-plan.txt
                    terraform -chdir=${TF_DIR} show -json dev.tfplan > reports/terraform-plan.json
                    rm -f ${TF_DIR}/dev.tfplan
                '''
            }
        }

        // ---------------- Build and ship ----------------

        stage('Docker Build') {
            steps {
                sh "docker build -t ${REGISTRY}/${DOCKER_CREDENTIALS_USR}/${IMAGE_NAME}:${IMAGE_TAG} ."
            }
        }

        stage('Trivy Scan') {
            steps {
                sh "trivy image --exit-code 0 --severity HIGH,CRITICAL --format json -o reports/trivy-report.json ${REGISTRY}/${DOCKER_CREDENTIALS_USR}/${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }

        // `branch 'main'` only evaluates in Multibranch jobs. A plain Pipeline
        // job reports the branch as GIT_BRANCH=origin/main, so check both.
        stage('Push') {
            when {
                expression { (env.BRANCH_NAME ?: env.GIT_BRANCH ?: '').endsWith('main') }
            }
            steps {
                // Single-quoted: the shell reads the secret from its environment,
                // so it is never interpolated into the script text or the log.
                sh 'echo "$DOCKER_CREDENTIALS_PSW" | docker login "$REGISTRY" -u "$DOCKER_CREDENTIALS_USR" --password-stdin'
                sh 'docker push "$REGISTRY/$DOCKER_CREDENTIALS_USR/$IMAGE_NAME:$IMAGE_TAG"'
            }
        }

        stage('Deploy') {
            when {
                expression { (env.BRANCH_NAME ?: env.GIT_BRANCH ?: '').endsWith('main') }
            }
            steps {
                // deploy.sh applies the manifests, pins the SHA-tagged image,
                // waits for rollout and checks /health inside a new pod.
                sh "scripts/deploy.sh ${REGISTRY}/${DOCKER_CREDENTIALS_USR}/${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }

        stage('Configuration Management') {
            when {
                expression { (env.BRANCH_NAME ?: env.GIT_BRANCH ?: '').endsWith('main') }
            }
            steps {
                // Converges both hosts with the same playbook operators run by
                // hand. Runtime secrets are read from SSM Parameter Store with
                // the host's instance role (no vault file, no Jenkins secret);
                // only the SSH key comes from Jenkins Credentials, as a temp
                // file whose path overrides the ~/.ssh path in ansible.cfg.
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'crra-ssh-key', keyFileVariable: 'ANSIBLE_PRIVATE_KEY_FILE')
                ]) {
                    sh '''#!/usr/bin/env bash
                        set -euo pipefail
                        cd ansible
                        ansible --version | head -1
                        ansible-playbook playbooks/site.yml 2>&1 | tee ../reports/ansible-site.txt
                    '''
                }
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
