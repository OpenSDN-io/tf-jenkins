import groovy.json.JsonSlurperClassic
import groovy.json.JsonOutput

// TODO: Fill up list of projects that can't be run in concurrent mode
SERIAL_PROJECTS = [
  'opensdn-io/tf-kolla-ansible',
]

// Function find base build fits to be the base build
// get its base builds list if any, and then iterate over the list
// check if items of the list is still working or SUCCESS or FAILURE.
// If next build is fit to be a base build, the function add its id to BASE_BUILDS_LIST
// return false if base build not found or build_id if foundпше
// save BASE_BUILD_ID_LIST sting including base builds chain like "23,22,20"
def save_base_builds() {
  def build_map = _prepare_build_map()
  println("DEBUG: build_map = ${build_map}")

  def current_build_id = env.BUILD_ID.toInteger()
  def base_build_id = null
  def base_chain = null
  for (build_id in build_map.keySet()) {
    def build_data = build_map[build_id]
    println("DEBUG: Parse build ${build_id}")
    // Skip current or later builds
    if (!_is_branch_fit(build_data['branch']) || build_id >= current_build_id) {
      println("DEBUG: build skipped")
      continue
    }

    if (build_data['status']) {
      // build has been finished
      if (check_build_successed(build_id)) {
        // We do not need base build!
        println("DEBUG: previous build is finished successfully. Stop searching. Base build is not found. Just run.")
        break
      }
      // else just skip the build
      println("DEBUG: build skipped")
    } else {
      // build is running
      // Wait for build chain will be prepared - wait for BASE_BUILD_ID_LIST in base build
      println("DEBUG: calculate chain")
      base_chain = _wait_for_chain_calculated(build_id)
      if (base_chain == null) {
        // build fails before can calculate BASE_BUILD_ID_LIST
        println("DEBUG: calculation failed. build skipped")
        continue
      }
      if (base_chain.length() == 0) {
        // base_chain is empty, add the only this build to chain
        base_chain = build_id.toString()
      } else {
        // base_chain is not empty string
        if (_check_base_chain_failed(base_chain)) {
          // Some of base builds fails
          println("DEBUG: Something failed. build skipped")
          continue
        }
        base_chain = "${build_id}," + base_chain
      }
      println("DEBUG: base_chain = ${base_chain}")
      // We found base build!
      println("DEBUG: base build found")
      base_build_id = build_id
      break
    }
  }

  if (base_build_id) {
      // We found base build! Save base_chain in global.vars
      sh """#!/bin/bash -e
        echo "export BASE_BUILD_ID_LIST=${base_chain}" >> global.env
      """
    // Add base patchset info to the build
    _save_pachset_info(base_build_id)
  } else {
    // If a base build not found save BASE_BUILD_ID_LIST anyway, because it requires
    // to detect if process of the base build search is finished
    sh """#!/bin/bash -e
      echo "export BASE_BUILD_ID_LIST=" >> global.env
    """
  }

  archiveArtifacts(artifacts: 'global.env')

  return base_build_id
}

// Function find build with build_id and takes its global env.
// Read global.env and wait until variable BASE_BUILD_ID_LIST will be added there
// or if build failed.
// return value of BASE_BUILD_ID_LIST if it was found or null if build fails
def _wait_for_chain_calculated(Integer build_id) {
  def base_id_list = null
  waitUntil {
    (build_finished, base_id_list) = _find_base_list_by_id(build_id)
    if (build_finished && base_id_list == null) {
      // build finished but no base_id_list was found
      return true
    }
    // returns boolean explicetly
    return base_id_list != null
  }

  return base_id_list
}

// Function get global.env artifact and find there BASE_BUILD_ID_LIST
// Returns value of BASE_BUILD_ID_LIST of has been found
// Otherwise return null
@NonCPS
def _find_base_list_by_id(Integer build_id) {
  def build = _get_build_by_id(build_id)
  def build_finished = build.getResult() != null
  def artifactManager = build.getArtifactManager()
  if (!artifactManager.root().isDirectory())
    return [build_finished, null]

  for (file in artifactManager.root().list()) {
    if (!file.toString().contains('global.env'))
      continue

    // extract global.env artifact for each build if exists
    def fileText = file.open().getText()
    // Check if BASE_BUILD_ID_LIST exists in global.env file
    def line = fileText.readLines().find() { item -> item && item.split('=')[0].split()[-1] == 'BASE_BUILD_ID_LIST' }
    if (!line)
      continue

    def parts = line.split('=')
    def result = parts.size() > 1 ? parts[1].trim() : ''
    return [build_finished, result]
  }

  return [build_finished, null]
}

// Function find the build with build_id and wait it finishes with any result
def wait_pipeline_finished(Integer build_id) {
  waitUntil {
    // Put all this staff in separate function due to Serialisation under waitUntil
    return get_build_result_by_id(build_id) != null
  }
}

// Function check build using build_id is failed or not
// The function get build's artifacts, find there VERIFIED,
// and check if it is integer and more than 0 return SUCCESS
// and return FAILRUE in another case
// !!! Works only if build has been finished! Check getResult() before call this function
@NonCPS
def check_build_successed(Integer build_id) {
  println("DEBUG: check_build_successed for ${build_id}")
  def build = _get_build_by_id(build_id)
  def artifactManager = build.getArtifactManager()
  if (!artifactManager.root().isDirectory()) {
    println("DEBUG: check_build_successed: root is not directory. return false")
    return false
  }

  for (file in artifactManager.root().list()) {
    if (!file.toString().contains('global.env'))
      continue
    // extract global.env artifact for each build if exists
    def fileText = file.open().getText()
    def line = fileText.readLines().find() { item -> item && item.split('=')[0].split()[-1] == 'VERIFIED' }
    if (!line) {
      println("DEBUG: check_build_successed: there is no VERIFIED line. return false")
      return false
    }
    def verified = line.split('=').size() > 1 ? line.split('=')[1].trim().toInteger() : 0
    println("DEBUG: check_build_successed: return ${verified} > 0")
    return verified > 0
  }

  println("DEBUG: check_build_successed: There is no global.env file. return false")
  return false
}

@NonCPS
def get_build_result_by_id(Integer build_id) {
  def build = _get_build_by_id(build_id)
  // TODO: think about cases when build is null
  def result = build.getResult()
  return result ? result.toString() : null
}

// find and return build of gate pipeline using build_id
// otherwise return null
@NonCPS
def _get_build_by_id(Integer build_id) {
  return Jenkins.getInstanceOrNull().getItem(env.JOB_NAME).getBuildByNumber(build_id)
}

// Function parse base chain and check if all builds is not failed
// if function meet successfully finished build in the chain, this
// build and all its base builds remove from the chain (chain shortened)
// Return true if it does NOT found failure build and chain
// and false if it founds some failures
def _check_base_chain_failed(base_chain) {
  if (base_chain.length() == 0)
    return false
  for (def build_id in base_chain.split(",")) {
    // is not finished yet - skip the build
    if (get_build_result_by_id(build_id.toInteger()) != null && !check_build_successed(build_id.toInteger()))
      return true
  }

  return false
}

// Function return ordered map with builds with data needed for find
// and process base build
def _prepare_build_map() {
  def build_map = [:]
  for (def build in Jenkins.getInstanceOrNull().getItem(env.JOB_NAME).builds) {
    if (!build || !build.getId())
      continue
    def result = build.getResult()
    if (result && result.toString() in ['UNSTABLE', 'ABORTED']) {
      // skip 'not ready to gate' builds
      continue
    }
    def build_id = build.getId().toInteger()
    def build_env = build.getEnvironment()

    build_map[build_id] = [
      'status' : result ? result.toString() : null ,
      'branch' : build_env['GERRIT_BRANCH'],
      'project' : build_env['GERRIT_PROJECT']
    ]
  }

  return build_map
}

// function return true if project can be run concurrently -
// it has contrail releases/branches structure
// otherwise it returns false
def is_concurrent_project() {
  // TODO: think about checking for concurrent project in patchsets_info
  return !SERIAL_PROJECTS.contains(env.GERRIT_PROJECT)
}

// Function check if build's branch fit to current project branch
// Return true if we can use this build as a base build for current running pipeline
// Otherwise return false
def _is_branch_fit(def branch) {
  if (is_concurrent_project()) {
    // Project has contrail releases structure
    // Branch of the base build must be the same
    if (branch != env.GERRIT_BRANCH)
      return false
  } else {
    // Project has its own releases structure
    // Branch of the base build must be master
    if (branch != 'master')
      return false
  }

  return true
}

// Check if pipeline with the same GERRIT_PROJECT is running
// and if it is then wait until finishes
def wait_until_project_pipeline() {
  def build_map = _prepare_build_map()
  for (build_id in build_map.keySet()) {
    def build_data = build_map[build_id]
    if (build_data['project'] != env.GERRIT_PROJECT || build_id >= env.BUILD_ID.toInteger())
      continue

    println("DEBUG: waiting for build to finish - ${build_id} ${build_data}")
    if (build_data['status'] == null) {
      waitUntil(initialRecurrencePeriod: 15000) {
        return get_build_result_by_id(build_id) != null
      }
    }
    // build has reversed order - if latest build finished then it's enough
    break
  }
}

// function read patchset_info artiface from base build if exists
// read pachset_info of current build
// union all patchset_info in one array
// and write all info to patchset_info artifact of corrent build
def _save_pachset_info(Integer base_build_id) {
  def res_json = _get_result_patchset(base_build_id)
  if (!res_json) {
    println("DEBUG: _get_result_patchset returned null... looks like it's an error.")
    throw("_get_result_patchset returned null")
  }
  writeFile(file: 'patchsets-info.json', text: res_json)
  archiveArtifacts(artifacts: "patchsets-info.json")
}

// all JSON calsulate to separate function
def _get_result_patchset(Integer base_build_id) {
  def new_patchset_info_text = readFile("patchsets-info.json")
  def sl = new JsonSlurperClassic()
  def new_patchset_info = sl.parseText(new_patchset_info_text)
  def base_patchset_info_text = ""
  // Read patchsets-info from base build
  def base_build = _get_build_by_id(base_build_id)
  def artifactManager = base_build.getArtifactManager()
  if (artifactManager.root().isDirectory()) {
    def fileList = artifactManager.root().list()
    fileList.any {
      def file = it
      if (file.toString().contains('patchsets-info.json')) {
        // extract global.env artifact for each build if exists
        base_patchset_info_text = it.open().getText()
        return true
      }
    }
  }
  def sl2 = new JsonSlurperClassic()
  def base_patchset_info = sl2.parseText(base_patchset_info_text)
  if (!(base_patchset_info instanceof java.util.ArrayList))
    return false

  // add absent items to base_patchset_info from new_patchset_info and return it
  def ids = []
  for (item in base_patchset_info)
    ids.add(item['id'])
  for (item in new_patchset_info)
    if (!ids.contains(item['id']))
      base_patchset_info.add(item)
  def result_patchset_info_text = JsonOutput.toJson(base_patchset_info)
  return result_patchset_info_text
}

// Function read global.env line by len and if met the line
// with BASE_BUILD_ID_LIST remove it from file
def cleanup_globalenv_vars() {
  def result = []
  def global_env = readFile("global.env")
  for (line in global_env.split('\n'))
    if (!line.contains('BASE_BUILD_ID_LIST'))
      result.add(line)
  writeFile(file: "global.env", text: result.join('\n') + '\n')
  archiveArtifacts(artifacts: 'global.env')
}

return this