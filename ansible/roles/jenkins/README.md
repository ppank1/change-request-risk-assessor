# jenkins

Installs Java 17 and Jenkins (LTS apt repo), adds `jenkins` to the `docker` group, installs `kubectl`, and **owns the Jenkins root URL** by templating `jenkins.model.JenkinsLocationConfiguration.xml` from `jenkins_url` (set to the Elastic IP in `group_vars`). Changing the URL or group membership triggers `Restart jenkins`.

This is the permanent fix for the Phase 0 incident: the URL is asserted by code on every run instead of living only in the UI.

Variables: `jenkins_url`, `jenkins_admin_email`, `jenkins_java_package`, `jenkins_kubectl_url`, `jenkins_home`.
