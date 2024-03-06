// config utils

import groovy.lang.GroovyShell

def get_templates_jobs(template_names) {
  def data = _get_data()
  def templates = _resolve_templates(data)

  def streams = [:]
  def jobs = [:]
  def post_jobs = [:]
  def branch = ''
  _add_templates_jobs(branch, template_names, templates, streams, jobs, post_jobs)

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
  def data = _get_data()

  // get templates
  def templates = _resolve_templates(data)

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
  // merge info from templates with project's jobs
  _update_map(streams, project[gerrit_pipeline].getOrDefault('streams', [:]))
  _update_map(jobs, project[gerrit_pipeline].getOrDefault('jobs', [:]))
  _update_map(post_jobs, project[gerrit_pipeline].getOrDefault('post-jobs', [:]))
  // then add templates to maintain higher precedence for job's definitions
  if (project[gerrit_pipeline].containsKey('templates')) {
    _add_templates_jobs(gerrit_branch, project[gerrit_pipeline].templates, templates, streams, jobs, post_jobs)
  }

  // set empty dict for dicts without params
  _set_default_values(streams)
  _set_default_values(jobs)
  _set_default_values(post_jobs)
  // do some checks
  // check if all deps point to real jobs
  _check_dependencies(jobs)
  _check_dependencies(post_jobs)
  _fill_stream_jobs(streams, jobs)

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

def _get_data() {
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
  return data
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
      def template = item['template']
      if (!template.containsKey('streams'))
        template['streams'] = [:]
      if (!template.containsKey('jobs'))
        template['jobs'] = [:]
      if (!template.containsKey('post-jobs'))
        template['post-jobs'] = [:]
      templates[template.name] = template
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
    if (item.getClass() != java.util.LinkedHashMap$Entry) {
      throw new Exception("Invalid item in config - '${item}'. It must be an entry of HashMap")
    }
    if (!items.containsKey(item.key) || items[item.key] == null)
      items[item.key] = item.value
    else if (item.value != null) {
      if (item.value.getClass() == java.util.LinkedHashMap) {
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
