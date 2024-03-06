slaves = [
  'aws': [
    [$class: 'AmazonWebServicesCredentialsBinding',
      credentialsId: 'aws-creds',
      accessKeyVariable: 'AWS_ACCESS_KEY_ID',
      secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']],
  'openstack': [
    string(credentialsId: 'OS_USERNAME', variable: 'OS_USERNAME'),
    string(credentialsId: 'OS_PROJECT_ID', variable: 'OS_PROJECT_ID'),
    string(credentialsId: 'OS_PASSWORD', variable: 'OS_PASSWORD'),
    string(credentialsId: 'OS_DOMAIN_NAME', variable: 'OS_USER_DOMAIN_NAME'),
    string(credentialsId: 'OS_DOMAIN_NAME', variable: 'OS_PROJECT_DOMAIN_NAME'),
    string(credentialsId: 'OS_AUTH_URL', variable: 'OS_AUTH_URL')]
]

timestamps {
  timeout(time: 10, unit: 'MINUTES') {
    def jobs_code = [:]
    slaves.keySet().each { label ->
      if (nodesByLabel(label).size() > 0) {
        jobs_code[label] = {
          node(label: label) {
            stage("Cleanup stalled workers on slaves ${label}") {
              clone_self()
              withCredentials(bindings: slaves[label]) {
                sh """
                  export SLAVE="${label}"
                  $WORKSPACE/src/opensdn-io/tf-jenkins/infra/${label}/cleanup_stalled_workers.sh
                """
              }
            }
          }
        }
      }
    }
    if (jobs_code.size() > 0)
      parallel(jobs_code)
  }
}

def clone_self() {
  checkout([
    $class: 'GitSCM',
    branches: [[name: "*/master"]],
    doGenerateSubmoduleConfigurations: false,
    submoduleCfg: [],
    userRemoteConfigs: [[url: 'https://github.com/opensdn-io/tf-jenkins.git']],
    extensions: [
      [$class: 'CleanBeforeCheckout'],
      [$class: 'CloneOption', depth: 1],
      [$class: 'RelativeTargetDirectory', relativeTargetDir: 'src/opensdn-io/tf-jenkins']
    ]
  ])
}
