// Gerrit utils

VERIFIED_STARTED_VALUES = ['check': 0, 'gate': 0, 'nightly': null, 'templates': null, 'stage-repos': null, 'init-repos': null]
VERIFIED_SUCCESS_VALUES = ['check': 1, 'gate': 2, 'nightly': 1, 'templates': null, 'stage-repos': 1, 'init-repos': 1]
VERIFIED_FAIL_VALUES = ['check': -1, 'gate': -2, 'nightly': -1, 'templates': null, 'stage-repos': -1, 'init-repos': -1]

def resolve_gerrit_url() {
  def url = "https://${env.GERRIT_HOST}/"
  while (true) {
    def getr = new URL(url).openConnection()
    getr.setFollowRedirects(false)
    if (((int)(getr.getResponseCode() / 100)) != 3)
      break
    url = getr.getHeaderField("Location")
  }
  println("INFO: resolved gerrit URL is ${url}")
  return url
}

def gerrit_build_started() {
  try {
    def msg = """TF CI Build Started (${env.GERRIT_PIPELINE}) ${BUILD_URL}"""
    notify_gerrit(msg, VERIFIED_STARTED_VALUES[env.GERRIT_PIPELINE])
  } catch (err) {
    println("Failed to provide comment to gerrit")
    def msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
  }
}

def publish_results(pre_build_done, streams, results, full_duration, err_msg=null) {
  try {
    if (!pre_build_done) {
      msg = "TF CI general failure (${env.GERRIT_PIPELINE})\n\n"
      if (err_msg)
        msg += "${err_msg}\n\n"
      msg += "Please check pipeline logs:\n"
      msg += "${BUILD_URL}\n${logs_url}\n"
      notify_gerrit(msg, VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE])
      return VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE]
    }

    def passed = true
    def check_msg_failed = ''
    def check_msg_skipped = ''
    def check_msg_succeeded = ''
    def stopping_cause = 'Failed'
    for (stream in results.keySet()) {
      println("Evaluated results for ${stream} = ${results[stream]}")
      def result = _get_stream_result(results[stream]['results'])
      def current_line = ''

      if (result == 'ABORTED') {
        stopping_cause = 'Aborted'
      }
      if (result == 'NOT_BUILT' || result == 'SKIPPED') {
        current_line = "\n- ${stream} : ${result}"
      } else {
        current_line = "\n- " + _get_gerrit_msg_for_job(stream, result, results[stream]['duration'])
      }
      def voting = true
      if (streams.containsKey(stream) && streams[stream].containsKey('voting')) {
        voting = streams[stream]['voting']
      } else if (jobs.containsKey(stream) && jobs[stream].containsKey('voting')) {
        voting = jobs[stream]['voting']
      }
      if (!voting) {
        current_line += ' (non-voting)'
      }
      // TODO: think how skipped builds should vote
      if (voting && result != 'SUCCESS') {
        passed = false
      }
      if (result == 'SKIPPED') {
        check_msg_skipped += current_line
      } else if (result != 'SUCCESS') {
        check_msg_failed += current_line
        // TODO: add name of failed job
      } else {
        check_msg_succeeded += current_line
      }
    }
    def check_msg = ''
    if (check_msg_failed)
      check_msg += "Failed checks:${check_msg_failed}\n\n"
    if (check_msg_skipped)
      check_msg += "Skipped checks:${check_msg_skipped}\n\n"
    check_msg += "Succeeded checks:${check_msg_succeeded}"

    def duration_string = _get_duration_string(full_duration)
    def verified = VERIFIED_SUCCESS_VALUES[env.GERRIT_PIPELINE]
    if (passed) {
      check_msg = "TF CI Build Succeeded (${env.GERRIT_PIPELINE}) ${duration_string}\n\n" + check_msg
    } else {
      check_msg = "TF CI Build ${stopping_cause} (${env.GERRIT_PIPELINE}) ${duration_string}\n\n" + check_msg
      verified = VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE]
    }
    notify_gerrit(check_msg, verified)
    return verified
  } catch (err) {
    println("Failed to provide vote to gerrit")
    local_err_msg = err.getMessage()
    if (local_err_msg != null)
      println("Message - ${local_err_msg}")
    println("Stacktrace - ${err.getStackTrace()}")
  }
  return 0
}

def report_timeline(job_results) {
  def segment = 300 // 5 minutes for 

  def startTime = 0
  def endTime = 0
  // job_results are not sorted by time - calculate startTime and endTime first
  for (job in job_results.keySet()) {
    if (job_results[job].containsKey('started') && job_results[job].containsKey('duration')) {
      if (job_results[job]['started'] < startTime || startTime == 0) {
        startTime = job_results[job]['started']
      }
      if (job_results[job]['started'] + job_results[job]['duration'] > endTime) {
        endTime = job_results[job]['started'] + job_results[job]['duration']
      }
    }
  }

  def output = ""
  for (job in job_results.keySet()) {
    result = job_results[job].getOrDefault('result', 'NOT_BUILT')
    hours = 0
    minutes = 0
    seconds = 0
    timeline = ''
    if (job_results[job].containsKey('started') && job_results[job].containsKey('duration')) {
      dashesBefore = (int) (job_results[job]['started'] - startTime) / segment / 1000
      duration = (int) (job_results[job]['duration'] / 1000)
      equals = (int) (duration + segment - 1) / segment
      seconds = (int) (duration % 60)
      minutes = (int) (duration / 60) % 60
      hours   = (int) (duration / 3600)
      timeline = "-"*dashesBefore + "="*equals
    }
    output += String.format("| %42s | %10s | %5d h %2d m %2d s | %s\n",
      job, result, hours, minutes, seconds, timeline)
  }

  def totalTime = endTime - startTime
  output += String.format("Total run time: %5d h %2d m %2d s\n",
    (int) (totalTime / (3600*1000)),
    (int) (totalTime / (60*1000)) % 60,
    (int) (totalTime % (60*1000) / 1000)
  )

  withCredentials(bindings: [sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    ssh_cmd = "ssh -i \$LOGS_HOST_SSH_KEY -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    ssh_dest = "\$LOGS_HOST_USERNAME@${constants.LOGS_HOST}"
    writeFile(file: 'timeline.log', text: output)
    sh """#!/bin/bash
      ${ssh_cmd} ${ssh_dest} "mkdir -p ${logs_path}"
      rsync -a -e "${ssh_cmd}" timeline.log ${ssh_dest}:${logs_path}/
    """
  }
  return totalTime
}

def publish_results_to_monitoring(streams, results, verified) {
  // TODO: handle flag pre_build_done - if it false then results will be empty
  // Log stream result

  // TODO: restore it
  return

  println("publish_results_to_monitoring: " + results)
  println(streams)

  if (env.GERRIT_PIPELINE == 'nightly')
    publish_nightly_results_to_monitoring(streams, results)
  else if (env.GERRIT_PIPELINE in ['check', 'gate'])
    publish_plain_results_to_monitoring(streams, results, verified)
}

def publish_plain_results_to_monitoring(streams, results, verified) {
  def optstostring = {
    it.collect { /--$it.key $it.value/ } join " "
  }

  def pipeline_result = verified < 0 ? "FAILURE" : "SUCCESS"
  for (stream in results.keySet()) {
    def result = _get_stream_result(results[stream]['results'])
    if (result == 'ABORTED') {
      pipeline_result = 'ABORTED'
      break
    }
  }

  try {
    def path = "c/${env.GERRIT_PROJECT}/+/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}"
    def log_opts = [
      gerrit: env.GERRIT_PIPELINE,
      status: pipeline_result,
      started: currentBuild.startTimeInMillis,
      duration: (new Date()).getTime() - currentBuild.startTimeInMillis,
      patchset: "${resolve_gerrit_url()}${path}",
      logs: logs_url,
      region: SLAVE_REGION
    ]

    logstring = optstostring(log_opts)
    sh """
      ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/fluentd/log.py \
        --host ${MONITORING_BACKEND_HOST} \
        ${logstring}
    """
  } catch (err) {
    println("Failed to send data to fluentd")
    err_msg = err.getMessage()
    if (err_msg != null)
      println("Message - ${err_msg}")
    println("Stacktrace - ${err.getStackTrace()}")
  }
}

def publish_nightly_results_to_monitoring(streams, results) {
  def optstostring = {
    it.collect { /--$it.key $it.value/ } join " "
  }

  for (stream in streams.keySet()) {
    def log_opts = [
      gerrit: env.GERRIT_PIPELINE,
      status: "NOT_IMPLEMENTED",
      duration: 0,
      started: currentBuild.startTimeInMillis,
      region: SLAVE_REGION
    ]
    if (results.containsKey(stream) && !results[stream].getOrDefault('skipped', false)) {
      log_opts['logs'] = "${logs_url}/${stream}"
      log_opts['status'] = _get_stream_result(results[stream]['results'])
      if (results[stream].containsKey('duration')) {
        log_opts['duration'] = results[stream]['duration']
      }
      if (results[stream].containsKey('started')) {
        log_opts['started'] = results[stream]['started']
      }
    }
    try {
      vars = streams[stream].getOrDefault('vars', [:])
      if (vars.containsKey('MONITORING_DEPLOY_TARGET') &&
          vars.containsKey('MONITORING_DEPLOYER') &&
          vars.containsKey('MONITORING_ORCHESTRATOR')) {

            log_opts['target'] = vars['MONITORING_DEPLOY_TARGET']
            log_opts['deployer'] = vars['MONITORING_DEPLOYER']
            log_opts['orchestrator'] = vars['MONITORING_ORCHESTRATOR']
      }

      logstring = optstostring(log_opts)
      sh """
        ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/fluentd/log.py \
          --host ${MONITORING_BACKEND_HOST} \
          ${logstring}
      """
    } catch (err) {
      println("Failed to send data to fluentd")
      err_msg = err.getMessage()
      if (err_msg != null)
        println("Message - ${err_msg}")
      println("Stacktrace - ${err.getStackTrace()}")
    }
  }
}

def _get_stream_result(def results) {
  // There are statuses available: NOT_BUILT, ABORTED, FAILURE, UNSTABLE, SUCCESS, SKIPPED
  if ('FAILURE' in results || 'UNSTABLE' in results)
    return 'FAILURE'
  if ('ABORTED' in results)
    return 'ABORTED'
  if ('SKIPPED' in results)
    return 'SKIPPED'
  // let's treat this as FAILURE. it can be caused by failures in deps
  if ('NOT_BUILT' in results && 'SUCCESS' in results)
    return 'FAILURE'
  return results[0]
}

def _get_gerrit_msg_for_job(stream, status, duration) {
  def duration_string = _get_duration_string(duration)
  return "${stream} ${logs_url}/${stream} : ${status} ${duration_string}"
}

def _get_duration_string(duration) {
  if (duration == null) {
    return ""
  }
  def d = (int)(duration/1000)
  return String.format("in %dh %dm %ds", (int)(d/3600), (int)(d/60)%60, d%60)
}

def notify_gerrit(msg, verified=0, submit=false, change_id=null, branch=null, patchset_number=null) {
  println("Notify gerrit verified=${verified}, submit=${submit}, msg=\n${msg}")
  if (!env.GERRIT_HOST) {
    if (env.GERRIT_PIPELINE == 'nightly') {
      // println('Temporarily disabled')
      emailext body: msg, subject: '[TF-JENKINS] Nightly build report', to: '$DEFAULT_RECIPIENTS'
    }
    return
  }

  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {
    def opts = ""

    if (verified != null) {
      opts += " --labels Verified=${verified}"
    }
    if (submit) {
      opts += " --submit"
    }
    def url = resolve_gerrit_url()
    if (!change_id)
      change_id = env.GERRIT_CHANGE_ID
    if (!branch)
      branch = env.GERRIT_BRANCH
    if (!patchset_number)
      patchset_number = env.GERRIT_PATCHSET_NUMBER

    // TODO: send comment by sha or patchset num
    sh """
      ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/gerrit/notify.py \
        --gerrit ${url} \
        --user \$GERRIT_API_USER \
        --password \$GERRIT_API_PASSWORD \
        --review ${change_id} \
        --patchset ${patchset_number} \
        --branch ${branch} \
        ${opts} \
        --message "${msg}"
    """
  }
}

def _has_approvals(strategy) {
  if (!env.GERRIT_HOST) {
    // looks like it's a nightly/stage pipeline
    return false
  }
  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {

    def url = resolve_gerrit_url()
    def output = ""
    try {
      output = sh(returnStdout: true, script: """
        ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/gerrit/check_approvals.py \
          --strategy ${strategy} \
          --gerrit ${url} \
          --user \$GERRIT_API_USER \
          --password \$GERRIT_API_PASSWORD \
          --review ${GERRIT_CHANGE_ID} \
          --branch ${GERRIT_BRANCH}
      """).trim()
      println(output)
      return true
    } catch (err) {
      println("check_approvals.py returns non-zero code. It means there is no approvals for now.")
      def msg = err.getMessage()
      if (msg != null) {
        println(msg)
      }
      return false
    }
  }
}

def resolve_patchsets() {
  res = sh(returnStatus: true, script: """
    ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/gerrit/resolve_patchsets.py \
      --gerrit ${gerrit_url} \
      --review ${GERRIT_CHANGE_ID} \
      --branch ${GERRIT_BRANCH} \
      --changed_files \
      --output ${WORKSPACE}/patchsets-info.json \
      2>script.err
  """)
  if (res != 0) {
    msg = ''
    if (fileExists('script.err'))
      msg = readFile("script.err")
    else
      msg = "Unknown error from script resolve_patchsets.py. Please check pipeline output."
    throw new Exception(msg)
  }
  archiveArtifacts(artifacts: 'patchsets-info.json')
}

def process_stale_reviews(strategy) {
  if (!env.GERRIT_HOST) {
    return
  }
  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {

    def url = resolve_gerrit_url()
    sh """
      ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/gerrit/process_stale_reviews.py \
        --strategy ${strategy} \
        --gerrit ${url} \
        --user \$GERRIT_API_USER \
        --password \$GERRIT_API_PASSWORD
    """
  }
}

def has_gate_approvals() {
  def result = _has_approvals('gate')
  println("INFO: has_gate_approvals = ${result}")
  return result
}

def has_gate_submits() {
  def result = _has_approvals('submit')
  println("INFO: has_submit_approvals = ${result}")
  return result
}

def is_merged() {
  if (!env.GERRIT_HOST) {
    // looks like it's a nightly/stage pipeline
    return false
  }
  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {

    def url = resolve_gerrit_url()
    def output = ""
    try {
      output = sh(returnStdout: true, script: """
        ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/gerrit/is_merged.py \
          --gerrit ${url} \
          --user \$GERRIT_API_USER \
          --password \$GERRIT_API_PASSWORD \
          --review ${GERRIT_CHANGE_ID} \
          --branch ${GERRIT_BRANCH}
      """).trim()
      println(output)
      return true
    } catch (err) {
      println("is_merged.py returns non-zero code. It means that review is not merged for now.")
      def msg = err.getMessage()
      if (msg != null) {
        println(msg)
      }
      return false
    }
  }
}

// block for termination utils

def terminate_runs_by_review_number() {
  // terminates pipeline for same review for previous patchset number
  def check = { action ->
    gerrit_change_number = action.getParameter("GERRIT_CHANGE_NUMBER")
    if (gerrit_change_number) {
      change_num = gerrit_change_number.value.toInteger()
      patchset_num = action.getParameter("GERRIT_PATCHSET_NUMBER").value.toInteger()
      if (env.GERRIT_CHANGE_NUMBER.toInteger() == change_num && env.GERRIT_PATCHSET_NUMBER.toInteger() > patchset_num)
        return true
    }
    return false
  }

  println("terminate_runs_by_review_number: start")
  terminated = _check_and_stop_builds(check)
  println("terminate_runs_by_review_number: terminated builds = ${terminated}")
  for (params in terminated) {
    _notify_terminated(params)
  }
}

def terminate_runs_by_depends_on_recursive(def change_id) {
  // recursive terminating
  println("Search for dependent builds for ${change_id}")
  def terminated = _terminate_runs_by_depends_on(change_id)
  println("terminate_runs_by_depends_on_recursive: terminated builds = ${terminated}")
  for (params in terminated) {
    _notify_terminated(params)
    terminate_runs_by_depends_on_recursive(params['change_id'])
  }
}

def _terminate_runs_by_depends_on(def change_id) {
  // terminates builds that have change_id in Depends-On:
  // returns terminated build's properties
  def check = { action ->
    def gerrit_change_commit_message = action.getParameter("GERRIT_CHANGE_COMMIT_MESSAGE")
    // TODO: check for same branch or related branches
    if (gerrit_change_commit_message) {
      // decodeBase64 return byte array
      def commit_message = new String(gerrit_change_commit_message.value.decodeBase64())
      def commit_dependencies = _get_dependencies_for_commit(commit_message)
      if (commit_dependencies.contains(change_id))
        return true
    }
    return false
  }

  return _check_and_stop_builds(check)
}

def _check_and_stop_builds(def check_func) {
  def terminated = []

  // sometimes loop for builds may fail with java.util.NoSuchElementException
  // let's do 3 retries
  for (def i = 0; i < 3; ++i) {
    try {
      def pipeline = Jenkins.getInstanceOrNull().getItemByFullName(env.JOB_NAME)
      def builds = pipeline.getBuildsAsMap().keySet()
      for (def buildNumber in builds) {
        def build = pipeline.getBuildByNumber(buildNumber)
        if (!build || !build.getResult().equals(null))
          continue
        def action = build.allActions.find { it in hudson.model.ParametersAction }
        if (!action)
          continue

        if (!check_func(action))
          continue

        terminated.add([
          'patchset_number': action.getParameter("GERRIT_PATCHSET_NUMBER").value.toInteger(),
          'change_id': action.getParameter("GERRIT_CHANGE_ID").value,
          'branch': action.getParameter("GERRIT_BRANCH").value
        ])

        build.doStop()
        println("Build ${build} has been aborted due to new patchset has been created for parent")
      }

      break
    } catch (err) {
      println("_check_and_stop_builds: Failed to iterate over builds")
      def msg = err.getMessage()
      if (msg != null) {
        println(msg)
      }
    }
  }

  return terminated
}

def _notify_terminated(def params) {
  try {
    def msg = """Run has been aborted due to new parent check ${env.GERRIT_CHANGE_ID} has been started."""
    notify_gerrit(msg, null, false, params['change_id'], params['branch'], params['patchset_number'])
  } catch (err) {
    println("Failed to provide comment to gerrit")
    def msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
  }
}

def _get_dependencies_for_commit(commit_message) {
  def deps = []
  try {
    for (line in commit_message.split('\n')) {
      if (line.toLowerCase().startsWith('depends-on')) {
        deps.add(line.split(':')[1].trim())
      }
    }
  } catch(err) {
    println('WARNING! Unable to parse dependency string')
    def msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
  }
  return deps
}

return this
