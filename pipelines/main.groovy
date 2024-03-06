// pipeline flow variables
// base url for all jobs
logs_url = ""
logs_path = ""

rnd = new Random()
gerrit_url = null

constants = null
// gerrit utils
gerrit_utils = null
// config utils
config_utils = null
// jobs utils
jobs_utils = null

// local constants
TIMEOUT_HOURS = 8
if (env.GERRIT_PIPELINE == 'nightly') {
  TIMEOUT_HOURS = 9
}

timestamps {
  timeout(time: TIMEOUT_HOURS, unit: 'HOURS') {
    node("${SLAVE}") {
      if (!env.GERRIT_CHANGE_ID && !(env.GERRIT_PIPELINE in ['nightly', 'stage-repos', 'init-repos'])) {
        println("Manual run is forbidden")
        return
      }

      stage('init') {
        try {
          cleanWs(disableDeferredWipeout: true, notFailBuild: true, deleteDirs: true)
          clone_self()

          gerrit_utils = load("${WORKSPACE}/src/opensdn-io/tf-jenkins/pipelines/utils/gerrit.groovy")
          if (env.GERRIT_CHANGE_ID) {
            // resolve gerrit_url for further usage
            gerrit_url = gerrit_utils.resolve_gerrit_url()
            // resolve patcchsets
            gerrit_utils.resolve_patchsets()
            // apply patchsets file onto tf-jenkins repo to get latest changes from review if exist
            res = sh(returnStatus: true, script: """#!/bin/bash -e
              export GERRIT_URL=${gerrit_url}
              ./src/opensdn-io/tf-jenkins/infra/gerrit/apply_patchsets.sh ./src opensdn-io/tf-jenkins ./patchsets-info.json 2>script.err
            """)
            if (res != 0) {
              msg = ''
              if (fileExists('script.err'))
                msg = readFile("script.err")
              else
                msg = "Unknown error from script apply_patchsets.sh. Please check pipeline output."
              throw new Exception(msg)
            }
            // always reload utils (if tf-jenkins in patchset's list)
            gerrit_utils = load("${WORKSPACE}/src/opensdn-io/tf-jenkins/pipelines/utils/gerrit.groovy")
          }

          constants = load("${WORKSPACE}/src/opensdn-io/tf-jenkins/pipelines/constants.groovy")
          config_utils = load("${WORKSPACE}/src/opensdn-io/tf-jenkins/pipelines/utils/config.groovy")
          jobs_utils = load("${WORKSPACE}/src/opensdn-io/tf-jenkins/pipelines/utils/jobs.groovy")
          gate_utils = load("${WORKSPACE}/src/opensdn-io/tf-jenkins/pipelines/utils/gate.groovy")
        } catch (err) {
          println(err.getMessage())
          msg = "TF CI Build Failed (${env.GERRIT_PIPELINE}) ${BUILD_URL}\n\n${err.getMessage()}"
          verified = gerrit_utils.notify_gerrit(msg, VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE])
          throw(err)
        }
      }

      jobs_utils.main(gate_utils, gerrit_utils, config_utils)
    }
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
