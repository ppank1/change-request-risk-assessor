#!/bin/bash
# Install Jenkins on Ubuntu/Debian
set -e

echo "=== Installing Jenkins ==="

# Install Java 17
sudo apt update
sudo apt install -y openjdk-17-jdk

# Add Jenkins repository
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Jenkins
sudo apt update
sudo apt install -y jenkins

# Start and enable Jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Add Jenkins to docker group for Docker access
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

echo "=== Jenkins installed successfully ==="
echo "Initial admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
