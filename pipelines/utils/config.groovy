// config utils

import groovy.lang.GroovyShell
import groovy.json.JsonSlurperClassic
import groovy.json.JsonOutput

def get_templates_jobs(templates_comment) {
  def data = _get_config_data()
  def templates_with_params = _parse_template_comment(templates_comment)
  def res = _update_config_data_from_template_comment(data, templates_with_params)
  def templates = _resolve_templates(res[0])
  println(templates.keySet())
  def templates_to_check = res[1]

  def streams = [:]
  def jobs = [:]
  def post_jobs = [:]
  _add_templates_jobs('', templates_to_check, templates, streams, jobs, post_jobs)

  // Set empty dict for dicts without params
  _set_default_values(streams)
  _set_default_values(jobs)
  _set_default_values(post_jobs)
  // Do some checks
  // Check if all deps point to real jobs
  _check_dependencies(jobs)
  _check_dependencies(post_jobs)
  _fill_stream_jobs(streams, jobs)

  return [streams, jobs, post_jobs]
}

def get_project_jobs(project_name, gerrit_pipeline, gerrit_branch) {
  // get data
  def data = _get_config_data()
  println(data)

  // get templates
  def templates = _resolve_templates(data)
  println(templates)

  // find project and pipeline inside it
  project = null
  for (item in data) {
    if (!item.containsKey('project'))
      continue
    if (item.get('project').containsKey('name') && item.get('project').name != project_name)
      continue
    if (item.get('project').containsKey('names') && !item.get('project').names.contains(project_name))
      continue
    if (item.get('project').containsKey('branch')) {
      def value = item.get('project').get('branch')
      found = _compare_branches(gerrit_branch, value)
      print("Found = ${found}, value = ${value}")
      if (!found) {
        continue
      }
    }

    project = item.get('project')
    break
  }
  // fill jobs from project and templates
  def streams = [:]
  def jobs = [:]
  def post_jobs = [:]
  if (!project) {
    println("INFO: project ${project_name} is not defined in config")
    return [streams, jobs, post_jobs]
  }
  if (!project.containsKey(gerrit_pipeline)) {
    print("WARNING: project ${project_name} doesn't define pipeline ${gerrit_pipeline}")
    return [streams, jobs, post_jobs]
  }
  println(project)
  // merge info from templates with project's jobs
  _update_map(streams, project[gerrit_pipeline].getOrDefault('streams', [:]))
  println("streams")
  println(streams)
  _update_map(jobs, project[gerrit_pipeline].getOrDefault('jobs', [:]))
  println("jobs")
  println(jobs)
  _update_map(post_jobs, project[gerrit_pipeline].getOrDefault('post-jobs', [:]))
  // then add templates to maintain higher precedence for job's definitions
  if (project[gerrit_pipeline].containsKey('templates')) {
    _add_templates_jobs(gerrit_branch, project[gerrit_pipeline].templates, templates, streams, jobs, post_jobs)
  }

  // set empty dict for dicts without params
  _set_default_values(streams)
  println("streams2")
  println(streams)
  _set_default_values(jobs)
  println("jobs2")
  println(jobs)
  _set_default_values(post_jobs)
  // do some checks
  // check if all deps point to real jobs
  _check_dependencies(jobs)
  _check_dependencies(post_jobs)
  _fill_stream_jobs(streams, jobs)
  println("streams3 + jobs2")
  println(streams)
  println(jobs)

  def sstreams = [:]
  def sjobs = [:]
  def spost_jobs = [:]
  return [sstreams, sjobs, spost_jobs]

  return [streams, jobs, post_jobs]
}

def _compare_branches(gerrit_branch, config_value) {
  def output_line = ''
  def branch = ''
  for (s in config_value) {
      if (s == ' ')
        continue
      if (s in ['!', '&', '|', '(', ')']) {
        output_line += _compare_branch(gerrit_branch, branch)
        output_line += s
        branch = ''
      }
      else
        branch += s
  }
  output_line += _compare_branch(gerrit_branch, branch)
  return _evaluate(output_line)
}

// this method uses regexp search that is no serializable - thus apply NonCPS
@NonCPS
def _compare_branch(gerrit_branch, config_branch) {
  // return true/false - otherwise it will return matcher object
  if (config_branch.length() == 0)
    return ''
  if (gerrit_branch =~ "^${config_branch}\$")
    return 'true'
  return 'false'
}

@NonCPS
def _evaluate(evaluate_string) {
  def shell = new GroovyShell()
  return shell.evaluate(evaluate_string)
}

def _get_config_data() {
  // read main file
  def data = readYaml(file: "${WORKSPACE}/src/opensdn-io/tf-jenkins/config/main.yaml")
  // read includes
  def include_data = []
  for (item in data) {
    if (item.containsKey('include')) {
      for (file in item['include']) {
        include_data += readYaml(file: "${WORKSPACE}/src/opensdn-io/tf-jenkins/config/${file}")
      }
    }
  }
  data += include_data

  // set defaults
  for (def item in data) {
    if (!item.containsKey('template')) {
      continue
    }
    def template = item['template']
    if (!template.containsKey('streams'))
      template['streams'] = [:]
    if (!template.containsKey('jobs'))
      template['jobs'] = [:]
    if (!template.containsKey('post-jobs'))
      template['post-jobs'] = [:]
    item['template'] = template
  }

  return data
}

def _parse_template_comment(templates_def) {
  // from gerrit comment:
  // templates_def = 'ansible-os  xxx  ansible-os ( ENVIRONMENT_OS : ubuntu20  )   ttt ansible-os (OPENSTACK_VERSION:ussuri,XXX:YYY)'
  // from jenkins/config it should be just a list
  // next code translates input string into map templates_list
  // [[ansible-os, [:]], [xxx, [:]], [ansible-os, [ENVIRONMENT_OS:ubuntu20]], [ttt, [:]], [ansible-os, [OPENSTACK_VERSION:ussuri, XXX:YYY]]]
  templates_def += ' '
  templates_list = []
  current=''
  for (i=0; i<templates_def.length(); i++) {
    if (templates_def[i] != ' ' && templates_def[i] != '(') {
      current += templates_def[i]
      continue
    }
    for (; i<templates_def.length(); i++) {
      if (templates_def[i] != ' ') {
        break
      }
    }
    if (i >= templates_def.length()) {
      templates_list += [[current, [:]]]
      break
    }
    vars = [:]
    if (templates_def[i] == '(') {
      params=''
    for (j=i+1; j<templates_def.length(); j++) {
        if (templates_def[j] == ')') {
          break
        }
        params += templates_def[j]
      }
      for (pair in params.split(',')) {
        kv = pair.split(':')
        if (kv.size() > 1) {
          vars[kv[0].trim()] = kv[1].trim()
        } else {
          vars[kv[0].trim()] = ''
        }
      }
      for (i=j+1; i<templates_def.length(); i++) {
        if (templates_def[i] != ' ') {
          break
        }
      }
    }
    templates_list += [[current, vars]]
    current = ''
    i -= 1
  }

  return templates_list
}

def _update_config_data_from_template_comment(data, templates_list) {
  def templates = [:]
  for (def item in data) {
    if (item.containsKey('template')) {
      templates[item['template'].name] = item['template']
    }
  }

  def templates_names = []
  for (template_def in templates_list) {
    def template_name = template_def[0]
    def vars = template_def[1]
    if (!templates.containsKey(template_name)) {
      throw new Exception("ERROR: template ${template_name} is absent in configuration")
    }
    // apply vars if exist
    if (vars.size() != 0) {
      // deep copy original template from config
      template = new JsonSlurperClassic().parseText(JsonOutput.toJson(templates[template_name]))
      template = _apply_vars_to_template(template, vars)
      data += ['template': template]
      template_name = template['name']
    }
    templates_names += template_name
  }

  return [data, templates_names]
}

def _apply_vars_to_template(template, vars) {
  suffix = '-' + vars.values().join('-')
  template['name'] = template['name'] + suffix
  for (s in template.getOrDefault('streams', [:]).keySet()) {
    if (s.length() == 0) {
      continue
    }
    def stream = template['streams'][s]
    if (!stream.containsKey('vars')) {
      stream['vars'] = [:]
    }
    for (k in vars.keySet()) {
      stream['vars'][k] = vars[k]
    }
    template['streams'][s + suffix] = stream
    template['streams'].remove(s)
  }
  job_names = template.getOrDefault('jobs', [:]).keySet()
  for (j in job_names) {
    if (j.length() == 0) {
      continue
    }
    job = template['jobs'][j] 
    if (!job.containsKey('job-name')) {
      job['job-name'] = j
    }
    if (job.containsKey('stream')) {
      job['stream'] = job['stream'] + suffix
    }
    deps = job.getOrDefault('depends-on', [])
    new_deps = []
    for (dep in deps) {
      if (job_names.contains(dep)) {
        new_deps += dep + suffix
      } else {
        new_deps += dep
      }
    }
    job['depends-on'] = new_deps

    template['jobs'][j + suffix] = job
    template['jobs'].remove(j)
  }
  return template
}

def _add_templates_jobs(gerrit_branch, template_names, templates, streams, jobs, post_jobs) {
  for (template in template_names) {
    def template_name = template instanceof String ? template : template.keySet().toArray()[0]
    if (!templates.containsKey(template_name)) {
      throw new Exception("ERROR: template ${template_name} is absent in configuration")
    }
    if (!(template instanceof String) && template[template_name].containsKey('branch')) {
      def value = template[template_name].get('branch')
      found = _compare_branches(gerrit_branch, value)
      print("Found = ${found}, value = ${value}")
      if (!found) {
        continue
      }
    }
    template = templates[template_name]
    _update_map(streams, template.getOrDefault('streams', [:]))
    _update_map(jobs, template.getOrDefault('jobs', [:]))
    _update_map(post_jobs, template.getOrDefault('post-jobs', [:]))
  }
}

def _set_default_values(def items) {
  for (def item in items.keySet()) {
    if (items[item] == null)
      items[item] = [:]
  }
}

def _check_dependencies(def jobs) {
  for (def item in jobs) {
    def deps = item.value.get('depends-on')
    if (deps == null || deps.size() == 0)
      continue
    for (def dep in deps) {
      def dep_name = dep instanceof String ? dep : dep.keySet().toArray()[0]
      if (!jobs.containsKey(dep_name))
        throw new Exception("Item ${item.key} has unknown dependency ${dep_name}")
    }
  }
}

def _resolve_templates(def config_data) {
  def templates = [:]
  for (def item in config_data) {
    if (item.containsKey('template')) {
      templates[item['template'].name] = item['template']
    }
  }
  // resolve parent templates
  while (true) {
    def parents_found = false
    def parents_resolved = false
    for (def item in templates) {
      if (!item.value.containsKey('parents'))
        continue
      parents_found = true
      def new_parents = []
      for (def parent in item.value['parents']) {
        if (!templates.containsKey(parent))
          throw new Exception("ERROR: Unknown parent: ${parent}")
        if (templates[parent].containsKey('parents')) {
          new_parents += parent
          continue
        }
        parents_resolved = true
        _update_map(item.value['streams'], templates[parent]['streams'])
        _update_map(item.value['jobs'], templates[parent]['jobs'])
        _update_map(item.value['post-jobs'], templates[parent]['post-jobs'])
      }
      if (new_parents.size() > 0)
        item.value['parents'] = new_parents
      else
        item.value.remove('parents')
    }
    if (!parents_found)
      break
    if (!parents_resolved)
      throw new Exception("ERROR: Unresolvable template structure: " + templates)
  }
  return templates
}

def _update_map(items, new_items) {
  for (item in new_items) {
    if (item.getClass() != java.util.LinkedHashMap$Entry && item.getClass() != java.util.TreeMap$Entry && item.getClass() != java.util.HashMap$Node) {
      throw new Exception("Invalid item in config - '${item} of type ${item.getClass()}'. It must be an entry of HashMap")
    }
    if (!items.containsKey(item.key) || items[item.key] == null)
      items[item.key] = item.value
    else if (item.value != null) {
      if (item.value.getClass() == java.util.LinkedHashMap || item.value.getClass() == java.util.TreeMap || item.value.getClass() == java.util.HashMap) {
        _update_map(items[item.key], item.value)
      } else if (item.value.getClass() == java.util.ArrayList) {
        for (val in item.value)
          if (!(val in items[item.key]))
            items[item.key].add(val)
      } else if (items[item.key] != item.value) {
        // it can be exception for some types but can be a normal situation for depends-on for example
        println("WARNING!!! " +
          "Invalid configuration - new item '${item}' with value type ${item.value.getClass()}' " +
          "has different value in current items: '${items[item.key]}' of type '${items[item.key].getClass()}")
      }
    }
  }
}

def _fill_stream_jobs(def streams, def job_set) {
  for (name in job_set.keySet()) {
    if (!job_set[name].containsKey('stream'))
      continue
    if (!streams.containsKey(job_set[name]['stream']))
      streams[job_set[name]['stream']] = [:]
    stream = streams[job_set[name]['stream']]
    if (!stream.containsKey('jobs')) {
      stream['jobs'] = []
    }
    stream['jobs'] += name
  }
}

return this
