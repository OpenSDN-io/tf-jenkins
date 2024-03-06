import java.text.SimpleDateFormat

// jobs utils

// set of result for each job
job_results = [:]

def main(def gate_utils, def gerrit_utils, def config_utils) {
  if (!_check_prerequisites())
    return

  def streams = [:]
  def jobs = [:]
  def post_jobs = [:]
  pre_build_done = false
  try {
    time_start = (new Date()).getTime()
    stage('Pre-build') {
      _evaluate_common_params()
      if (env.GERRIT_CHANGE_ID) {
        gerrit_utils.terminate_runs_by_review_number()
        // cancel dependent jobs (by Depends-On) only if new patchset was created
        if (env.GERRIT_EVENT_TYPE == 'patchset-created')
          gerrit_utils.terminate_runs_by_depends_on_recursive(env.GERRIT_CHANGE_ID)
      }
      (streams, jobs, post_jobs) = _evaluate_env(config_utils)
      gerrit_utils.gerrit_build_started()

      desc = []
      if (env.GERRIT_CHANGE_ID) {
        desc += "Branch: ${env.GERRIT_BRANCH}  Project: ${env.GERRIT_PROJECT}"
        msg_header = new String(env.GERRIT_CHANGE_COMMIT_MESSAGE.decodeBase64()).split('\n')[0]
        desc += "CommitMsg: ${msg_header.substring(0, msg_header.length() < 50 ? msg_header.length() : 50)}"
      }
      desc += "<a href='${logs_url}'>${logs_url}</a>"
      currentBuild.description = desc.join('<br>')
      pre_build_done = true
    }

    if (env.GERRIT_PIPELINE == 'gate')
      _run_gating(jobs, streams, gate_utils, gerrit_utils)
    else
      _run_jobs(jobs, streams)
  } finally {
    println("Jobs results: ${job_results}")
    stage('gerrit vote') {
      // add gerrit voting +2 +1 / -1 -2
      def results = _get_jobs_result_for_gerrit(jobs, job_results, streams)
      verified = gerrit_utils.publish_results(pre_build_done, streams, results, (new Date()).getTime() - time_start)
      sh """#!/bin/bash -e
        echo "export VERIFIED=${verified}" >> global.env
      """
      archiveArtifacts(artifacts: 'global.env')
      gerrit_utils.report_timeline(job_results)
      gerrit_utils.publish_results_to_monitoring(streams, results, verified)
    }
    if (pre_build_done) {
      try {
        _run_jobs(post_jobs, streams)
      } catch (err) {
      }
    }

    _save_pipeline_artifacts_to_logs(jobs, post_jobs)
  }
}

def _check_prerequisites() {
  if (env.GERRIT_PIPELINE == 'gate' && !gerrit_utils.has_gate_approvals()) {
    println("There is no gate approvals. skip gate")
    currentBuild.description = "Not ready to gate"
    currentBuild.result = 'UNSTABLE'
    return false
  }

  if (env.GERRIT_PIPELINE in ['check', 'gate'] && gerrit_utils.is_merged()) {
    println("Review already merged. skip ${env.GERRIT_PIPELINE}")
    currentBuild.description = "Already merged"
    currentBuild.result = 'UNSTABLE'
    return false
  }

  return true
}

def _evaluate_common_params() {
  // evaluate logs params
  branch = 'master'
  if (env.GERRIT_BRANCH)
    branch = env.GERRIT_BRANCH.split('/')[-1].toLowerCase()
  openstack_version = null
  if (branch in constants.OPENSTACK_VERSIONS)
    openstack_version = branch
  if (env.GERRIT_CHANGE_ID) {
    tf_container_tag = branch
    // we have to avoid presense of 19xx, 20xx, ... in tag - apply some hack here to indicate current patchset and avoid those strings
    // and we have to avoid 5.1 and 5.0 in tag
    tf_container_tag += '-' + env.GERRIT_CHANGE_NUMBER.split('').join('_')
    tf_container_tag += '-' + env.GERRIT_PATCHSET_NUMBER.split('').join('_')
    hash = env.GERRIT_CHANGE_NUMBER.reverse().take(2).reverse()
    logs_path = "${constants.LOGS_BASE_PATH}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
    logs_url = "${constants.LOGS_BASE_URL}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
  } else if (env.GERRIT_PIPELINE == 'nightly') {
    tf_container_tag = "nightly"
    logs_path = "${constants.LOGS_BASE_PATH}/nightly/pipeline_${BUILD_NUMBER}"
    logs_url = "${constants.LOGS_BASE_URL}/nightly/pipeline_${BUILD_NUMBER}"
  } else if (env.GERRIT_PIPELINE == 'stage-repos' || env.GERRIT_PIPELINE == 'init-repos') {
    tf_container_tag = "${env.GERRIT_PIPELINE}-${REPOS_TYPE}"
    logs_path = "${constants.LOGS_BASE_PATH}/${env.GERRIT_PIPELINE}-${REPOS_TYPE}/pipeline_${BUILD_NUMBER}"
    logs_url = "${constants.LOGS_BASE_URL}/${env.GERRIT_PIPELINE}-${REPOS_TYPE}/pipeline_${BUILD_NUMBER}"
  } else {
    tf_container_tag = 'dev'
    logs_path = "${constants.LOGS_BASE_PATH}/manual/pipeline_${BUILD_NUMBER}"
    logs_url = "${constants.LOGS_BASE_URL}/manual/pipeline_${BUILD_NUMBER}"
  }
  println("Logs URL: ${logs_url}")
}

def _evaluate_env(def config_utils) {
  try {
    sh """#!/bin/bash -e
      rm -rf global.env
      echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" >> global.env
      echo "export SLAVE=${SLAVE}" >> global.env
      echo "export SLAVE_REGION=${env.SLAVE_REGION}" >> global.env
      echo "export LOGS_HOST=${constants.LOGS_HOST}" >> global.env
      echo "export LOGS_PATH=${logs_path}" >> global.env
      echo "export LOGS_URL=${logs_url}" >> global.env
      # store default registry params. jobs can redefine them if needed in own config (VARS).
      echo "export SITE_MIRROR=${constants.SITE_MIRROR}" >> global.env

      echo "export CONTAINER_REGISTRY=${constants.CONTAINER_REGISTRY}" >> global.env
      echo "export DEPLOYER_CONTAINER_REGISTRY=${constants.CONTAINER_REGISTRY}" >> global.env
      echo "export CONTRAIL_CONTAINER_TAG=${tf_container_tag}" >> global.env
      echo "export CONTRAIL_DEPLOYER_CONTAINER_TAG=${tf_container_tag}" >> global.env

      echo "export CONTAINER_REGISTRY_ORIGINAL=${constants.CONTAINER_REGISTRY}" >> global.env
      echo "export DEPLOYER_CONTAINER_REGISTRY_ORIGINAL=${constants.CONTAINER_REGISTRY}" >> global.env
      echo "export CONTRAIL_CONTAINER_TAG_ORIGINAL=${tf_container_tag}" >> global.env
      echo "export CONTRAIL_DEPLOYER_CONTAINER_TAG_ORIGINAL=${tf_container_tag}" >> global.env

      echo "export GERRIT_PIPELINE=${env.GERRIT_PIPELINE}" >> global.env
    """
    if (openstack_version != null) {
      // let the project to define own default version
      sh """#!/bin/bash -e
        echo "export OPENSTACK_VERSION=${openstack_version}" >> global.env
      """
    }

    // store gerrit input if present. evaluate jobs
    println("Pipeline to run: ${env.GERRIT_PIPELINE}")
    project_name = env.GERRIT_PROJECT
    repos_channel = 'latest'
    if (env.GERRIT_CHANGE_ID) {
      sh """#!/bin/bash -e
        echo "export GERRIT_URL=${gerrit_url}" >> global.env
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
        echo "export GERRIT_PROJECT=${env.GERRIT_PROJECT}" >> global.env
      """
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      project_name = "opensdn-io"
      sh """#!/bin/bash -e
        echo "export GERRIT_BRANCH=master" >> global.env
      """
    } else if (env.GERRIT_PIPELINE == 'stage-repos' || env.GERRIT_PIPELINE == 'init-repos') {
      project_name = "${env.GERRIT_PIPELINE}-${REPOS_TYPE}"
      sh """#!/bin/bash -e
        echo "export GERRIT_BRANCH=master" >> global.env
        echo "export REPOS_TYPE=${REPOS_TYPE}" >> global.env
      """
      repos_channel = 'stage'
    }
    sh """#!/bin/bash -e
      echo "export REPOS_CHANNEL=${repos_channel}" >> global.env
    """
    archiveArtifacts(artifacts: 'global.env')

    if (env.GERRIT_PIPELINE != 'templates') {
      // Get jobs for the whole project
      (streams, jobs, post_jobs) = config_utils.get_project_jobs(project_name, env.GERRIT_PIPELINE, env.GERRIT_BRANCH)
    } else {
      // It triggers by comment "(check|recheck) template(s) name1 name2 ...".
      def full_comment = env.GERRIT_EVENT_COMMENT_TEXT.toLowerCase()
      def lines = full_comment.split("\n")
      def needed_line = ""
      for (line in lines) {
        if (line.startsWith("check") || line.startsWith("recheck")) {
          needed_line = line
          break
        }
      }
      if (needed_line == "") {
        throw new Exception("ERROR: strange comment message: ${full_comment}")
      }
      def template_names = needed_line.split()[2..-1]
      (streams, jobs, post_jobs) = config_utils.get_templates_jobs(template_names)
    }
    println("Streams from  config: ${streams}")
    println("Jobs from config: ${jobs}")
    println("Post Jobs from config: ${post_jobs}")
  } catch (err) {
    msg = err.getMessage()
    if (err != null) {
      println("ERROR: Failed set environment ${msg}")
    }
    throw(err)
  }
  return [streams, jobs, post_jobs]
}

def _run_gating(def jobs, def streams, def gate_utils, def gerrit_utils) {
  while (true) {
    def base_build_id = gate_utils.save_base_builds()
    try {
      if (gate_utils.is_concurrent_project()) {
        // Run immediately if projest can be run concurrently
        println("DEBUG: Concurrent project - run jobs")
        _run_jobs(jobs, streams)
      } else {
        // Wait for the same project pipeline is finishes
        println("DEBUG: Serial run - wait until finishes previous pipeline")
        gate_utils.wait_until_project_pipeline()
        println("DEBUG: Project in serial list - run jobs")
        _run_jobs(jobs, streams)
      }
    } finally {
      // Finish the loop if pipeline was aborted
      def result = gate_utils.get_build_result_by_id(env.BUILD_ID.toInteger())
      if (result == "ABORTED")
        break

      if (!base_build_id) {
        // we do not have base build - Just finish the job
        println("DEBUG: We do NOT have base pipeline. Finishing...")
        break
      }

      println("DEBUG: We found base pipeline ${base_build_id} and are waiting for base pipeline")
      gate_utils.wait_pipeline_finished(base_build_id)
      println("DEBUG: Base pipeline has been finished")
      if (gate_utils.check_build_successed(base_build_id)) {
        // Finish the pipeline if base build finished successfully
        // else try to find new base build
        println("DEBUG: Base pipeline has been verified")
        break
      } else {
        println("DEBUG: Base pipeline has not been verified. Run build again...")
      }

      // treat pipeline as restarted and cleanup vars in global.env
      // Delete BASE_BUILD_ID_LIST from global.env
      gate_utils.cleanup_globalenv_vars()
      // reset_patchset_info to start state
      gerrit_utils.resolve_patchsets()
    }
  }
}

def _run_jobs(def job_set, def streams) {
  // initialize all results
  def streams_to_run = []
  for (name in job_set.keySet()) {
    job_results[name] = [:]
    job_results[name]['job-rnd'] = "${rnd.nextInt(99999)}"
    if (job_set[name].get('stream') != null)
      streams_to_run += job_set[name].get('stream')
  }

  def all_code = [:]
  streams.keySet().each { stream_name ->
    if (stream_name in streams_to_run)
      all_code["stream-${stream_name}"] = { _process_stream(stream_name, job_set, streams) }
  }

  job_set.keySet().each { job_name ->
    if (job_set[job_name].get('stream') == null) {
      all_code["job-${job_name}"] = {
        _process_job(job_name, job_set, streams)
      }
    }
  }

  // run jobs in parallel
  if (all_code.size() > 0)
    parallel(all_code)
}

def _is_skipped(def name, def frequency) {
  def currentDate = new Date()
  // day of the Year from first Monday of year. 
  zeroDay = new SimpleDateFormat("yyyy-MM-dd").parse("${currentDate.getYear()+1900}-01-01")
  // -3 = -1(from numbers 1-7 to indexes 0-6) -2(shift first day of week from Saturday to Monday)
  day = currentDate[Calendar.DAY_OF_YEAR] + zeroDay[Calendar.DAY_OF_WEEK] - 3
  if ((day % frequency) != 0) {
    println("Stream/job {$name} has been skipped due to frequency=${frequency} (current day number is ${day}")
    return true
  }
  return false
}

def _process_stream(def stream_name, def job_set, def streams) {
  if (streams[stream_name].containsKey('frequency') && _is_skipped(stream_name, streams[stream_name]['frequency'])) {
    streams[stream_name]['skipped'] = true
    return
  }

  def jobs_code = [:]
  job_set.keySet().each { name ->
    if (job_set[name].get('stream') == stream_name)
      jobs_code[name] = {
        _process_job(name, job_set, streams)
      }
  }
  if (jobs_code.size() == 0)
    return

  if (!streams[stream_name].containsKey('lock')) {
    parallel(jobs_code)
  } else {
    lock(resource: streams[stream_name]['lock']) {
      parallel(jobs_code)
    }
  }
}

def _process_job(def job_name, def job_set, def streams) {
  // using global variable job_results
  stage(job_name) {
    try {
      def result = _wait_for_dependencies(job_set, job_name)
      if (result) {
        if (!job_set[job_name].containsKey('lock')) {
          _run_job(job_set, job_name, streams)
        } else {
          lock(resource: job_set[job_name]['lock']) {
            _run_job(job_set, job_name, streams)
          }
        }
      } else {
        job_results[job_name]['number'] = -1
        job_results[job_name]['duration'] = 0
        job_results[job_name]['result'] = 'NOT_BUILT'
      }
    } catch (err) {
      println("JOB ${job_name}: error in job!!!")
      println("JOB ${job_name}: Err - ${err}")
      println("JOB ${job_name}: Message - ${err.getMessage()}")
      println("JOB ${job_name}: Cause - ${err.getCause()}")
      println("JOB ${job_name}: Stacktrace - ${err.getStackTrace()}")
      throw(err)
    }
  }
}

def _get_jobs_result_for_gerrit(def job_set, def job_results, def streams) {
  def results = [:]
  for (name in job_set.keySet()) {
    // do not include post job into report
    if (job_set[name].getOrDefault('type', '').contains('no-report'))
      continue
    def stream = job_set[name].getOrDefault('stream', name)
    def job_result = job_results.get(name)
    def result = job_result != null ? job_result.getOrDefault('result', 'NOT_BUILT') : 'NOT_BUILT'
    def duration = job_result != null ? job_result.getOrDefault('duration', 0) : 0
    if (!results.containsKey(stream)) {
      results[stream] = ['results': [result], 'duration': duration]
    } else {
      results[stream]['results'] += result
      results[stream]['duration'] += duration
    }
  }
  for (name in results.keySet()) {
    if (streams.containsKey(name) && streams[name].getOrDefault('skipped', false))
      results[name]['results'] = ['SKIPPED']
  }
  return results
}

def _save_pipeline_artifacts_to_logs(def jobs, def post_jobs) {
  println("URL of console output = ${BUILD_URL}consoleText")
  withCredentials(bindings: [sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    ssh_cmd = "ssh -i \$LOGS_HOST_SSH_KEY -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    ssh_dest = "\$LOGS_HOST_USERNAME@${constants.LOGS_HOST}"
    sh """#!/bin/bash
      curl -sS ${BUILD_URL}consoleText > pipelinelog.log
      ${ssh_cmd} ${ssh_dest} "mkdir -p ${logs_path}"
      rsync -a -e "${ssh_cmd}" pipelinelog.log ${ssh_dest}:${logs_path}/
    """
  }
  println("Output logs saved at ${logs_url}/pipelinelog.txt")
}

def _wait_for_dependencies(job_set, name) {
  def deps = job_set[name].get('depends-on')
  if (deps == null || deps.size() == 0)
    return true
  println("JOB ${name}: waiting for dependecies")
  def post_hook = job_set[name].getOrDefault('type', '').contains('post-hook')
  def overall_result = true
  waitUntil(initialRecurrencePeriod: 15000) {
    def result_map = [:]
    for (def dep in deps) {
      def dep_name = dep instanceof String ? dep : dep.keySet().toArray()[0]
      result_map[dep_name] = job_results.containsKey(dep_name) ? job_results[dep_name].get('result') : null
    }
    println("JOB ${name}: waiting for dependecy ${result_map}")
    results = result_map.values()
    if (post_hook) {
      // wait while 'null' is still in any result of stream
      println("JOB ${name}: waiting for all = ${!results.contains(null)}")
      return !results.contains(null)
    }
    // otherwise stop waiting if someone failed
    if ('FAILURE' in results || 'UNSTABLE' in results || 'NOT_BUILT'in results || 'ABORTED' in results) {
      overall_result = false
      return true
    }
    // continue waiting if someone still is not ready
    if (null in results) {
      println("JOB ${name}: fails were not found, unfinished jobs are still present")
      return false
    }
    // here only SUCCESS is in the results - stop waiting
    return true
  }
  println("JOB ${name}: wait finished. overall result = ${overall_result}")
  return overall_result
}

def _job_params_to_file(def job_set, def name, def streams, def env_file) {
  if (!job_set.containsKey(name))
    return

  def job_name = job_set[name].getOrDefault('job-name', name)
  def env_text = ""
  def vars = [:]
  if (job_set[name].containsKey('stream')) {
    stream = streams.get(job_set[name]['stream'])
    if (stream && stream.containsKey('vars')) {
      vars += stream['vars']
    }
  }
  if (job_set[name].containsKey('vars'))
    vars += job_set[name]['vars']
  def vars_keys = vars.keySet() as List
  if (vars_keys.size() == 0) {
    println("JOB ${name}: vars empty. do not store vars file.")
    return
  }
  // simple for-loop to avoid non-Serializable exception
  for (def i = 0; i < vars_keys.size(); ++i) {
    env_text += "export ${vars_keys[i]}=\"${vars[vars_keys[i]]}\"\n"
  }
  writeFile(file: env_file, text: env_text)
  archiveArtifacts(artifacts: env_file)
}

def _collect_dependent_env_files(job_set, name, deps_env_file) {
  if (!job_set.containsKey(name) || !job_set[name].containsKey('depends-on'))
    return
  def deps = job_set[name].get('depends-on')
  if (deps == null || deps.size() == 0)
    return
  def stream = job_set[name].get('stream')
  println("JOB ${name} / stream ${stream} : deps: ${deps}")
  def raw_data = []
  // simple loop to avoid java.io.NotSerializableException: org.codehaus.groovy.util.ArrayIterator
  for (def i = 0; i < deps.size(); ++i) {
    def dep = deps[i]
    def dep_name = dep instanceof String ? dep : dep.keySet().toArray()[0]
    def dep_keys = dep instanceof String ? [] : dep[dep_name].get('inherit-keys', [])
    def dep_stream = job_set[dep_name].get('stream')
    def dep_job_name = job_set[dep_name].getOrDefault('job-name', dep_name)
    def dep_job_rnd = job_results[dep_name]['job-rnd']
    dir("${WORKSPACE}") {
      def files = findFiles(glob: "${dep_job_name}-${dep_job_rnd}/*.env")
      println("JOB ${name}: files found = ${files.size()}")
      for (def j = 0; j < files.size(); ++j) {
        println("JOB ${name}: file #${j} with path ${files[j].getPath()}")
        def data = readFile(files[j].getPath()).split('\n')
        // env should be filtered if any jobs is a stream job (but not both) or they from different streams
        if (stream != dep_stream) {
          println("streams are different (${stream} != ${dep_stream}). env should be filtered only for keys '${dep_keys}'")
          // simple loop to avoid java.io.NotSerializableException: org.codehaus.groovy.util.ArrayIterator
          // https://issues.jenkins-ci.org/browse/JENKINS-47730
          def filtered_data = []
          for (def k = 0; k < data.size(); ++k)
            if (data[k] && data[k].split('=')[0].split(' ')[-1] in dep_keys)
              filtered_data += data[k]
          data = filtered_data
        }
        if (files[j].getName().startsWith("deps."))
          raw_data.addAll(0, data)
        else
          raw_data.addAll(data)
      }
    }
  }
  def lines = []
  for (def i = 0; i < raw_data.size(); ++i) {
    def line = raw_data[i]
    if (line.size() > 0 && !lines.contains(line))
      lines += line
  }
  if (lines.size() == 0) {
    println("JOB ${name}: content of deps file is empty")
    return
  }
  println("JOB ${name}: deps_env_file: ${deps_env_file}")
  writeFile(file: deps_env_file, text: lines.join('\n') + '\n')
  archiveArtifacts(artifacts: deps_env_file)
}

// this method uses regexp search that is no serializable - thus apply NonCPS
@NonCPS
def _get_job_number_from_exception(def run_err) {
  def causes = run_err.getCauses()
  if (causes == null || causes.size() == 0)
    return null
  def cause_msg = causes[0].getShortDescription()
  def build_num_matcher = cause_msg =~ /#\d+/
  if (build_num_matcher.find())
    return ((build_num_matcher[0] =~ /\d+/)[0]).toInteger()
  return null
}

def _run_job(def job_set, def name, def streams) {
  println("JOB ${name}: entering run_job")
  // final cleanup job is not in config
  def job_name = job_set[name].getOrDefault('job-name', name)
  def stream = job_set[name].getOrDefault('stream', name)
  def timeout_value = job_set[name].getOrDefault('timeout', constants.JOB_TIMEOUT) as int
  def job_params = job_set[name].getOrDefault('job-params', [:])
  def job_rnd = job_results[name]['job-rnd']
  def vars_env_file = "vars.${job_name}.${job_rnd}.env"
  def deps_env_file = "deps.${job_name}.${job_rnd}.env"
  def job_number = null
  def run_err = null
  try {
    _job_params_to_file(job_set, name, streams, vars_env_file)
    _collect_dependent_env_files(job_set, name, deps_env_file)
    def params = [
      string(name: 'STREAM', value: stream),
      string(name: 'JOB_RND', value: job_rnd),
      string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
      string(name: 'PIPELINE_NUMBER', value: "${BUILD_NUMBER}"),
      [$class: 'LabelParameterValue', name: 'NODE_NAME', label: "${NODE_NAME}"]]
    if (job_params) {
      for (param in job_params) {
        params.add(string(name: param.key, value: param.value))
      }
    }
    println("JOB ${name}: Starting job: ${job_name}  rnd: #${job_rnd}")
    timeout(time: timeout_value, unit: 'MINUTES') {
      def job = build(job: job_name, parameters: params)
      job_number = job.getNumber()
      job_results[name]['number'] = job_number
      job_results[name]['started'] = job.getStartTimeInMillis()
      job_results[name]['duration'] = job.getDuration()
      job_results[name]['result'] = job.getResult().toString()
      println("JOB ${name}: Finished with SUCCESS")
    }
  } catch (err) {
    run_err = err
    job_results[name]['result'] = 'FAILURE'
    println("JOB ${name}: Failed")
    def msg = err.getMessage()
    if (msg != null) {
      println("JOB ${name}: err msg: ${msg}")
    }
    // get build num from exception and find job to get duration and result
    try {
      job_number = _get_job_number_from_exception(run_err)
      if (job_number) {
        def job = Jenkins.getInstanceOrNull().getItemByFullName(job_name).getBuildByNumber(job_number)
        job_results[name]['number'] = job_number
        job_results[name]['started'] = job.getStartTimeInMillis()
        job_results[name]['duration'] = job.getDuration()
        job_results[name]['result'] = job.getResult().toString()
      }
    } catch(e) {
      println("JOB ${name}: Error in obtaining failed job result ${e.getMessage()}")
    }
  }
  if (job_number != null) {
    target_dir = "${job_name}-${job_rnd}"
    copyArtifacts(
      filter: '*.env',
      excludes: "global.env,${vars_env_file}",
      optional: true,
      fingerprintArtifacts: true,
      projectName: job_name,
      selector: specific("${job_number}"),
      target: target_dir)
    println("JOB ${name}: Collected artifacts:")
    sh("ls -la ${target_dir} || /bin/true") // folder can be absent
    _save_job_output(name, job_name, stream, job_number)
  }
  // re-throw error
  if (run_err != null)
    throw run_err
}

def _save_job_output(name, job_name, stream, job_number) {
  withCredentials(bindings: [sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    ssh_cmd = "ssh -i \$LOGS_HOST_SSH_KEY -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    ssh_dest = "\$LOGS_HOST_USERNAME@${constants.LOGS_HOST}"
    sh """#!/bin/bash
      curl -sS ${JENKINS_URL}job/${job_name}/${job_number}/consoleText > output-${name}.log
      ${ssh_cmd} ${ssh_dest} "mkdir -p ${logs_path}/${stream}/"
      rsync -a -e "${ssh_cmd}" output-${name}.log ${ssh_dest}:${logs_path}/${stream}/
    """
    // hack for better visibility of UT failures
    sh """#!/bin/bash
      if grep -q '^ERROR.*failed\$' output-${name}.log ; then
        grep '^ERROR.*failed\$' output-${name}.log > output-${name}-FAILED.log
        rsync -a -e "${ssh_cmd}" output-${name}-FAILED.log ${ssh_dest}:${logs_path}/${stream}/
      fi
    """
  }
}

return this
