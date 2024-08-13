timestamps {
  def instance = Jenkins.getInstanceOrNull()
  def runningBuilds = instance.getView('All').getBuilds().findAll() { it.getResult().equals(null) }
  runningBuilds.removeAll { it.grep( ~/pipeline-abandon.*/ ) }
  for (rb in runningBuilds) {
    if (rb.allActions.find {it in hudson.model.ParametersAction}.getParameter("GERRIT_CHANGE_NUMBER") != null ) {
      change_num = rb.allActions.find {it in hudson.model.ParametersAction}.getParameter("GERRIT_CHANGE_NUMBER").value.toInteger()
      if (GERRIT_CHANGE_NUMBER.toInteger() == change_num) {
        rb.doStop()
        println "Build $rb has been aborted"
      }
    }
  }
}
