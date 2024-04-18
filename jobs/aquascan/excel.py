#!/usr/bin/env python3

import os
import sys
import json
import getopt
import xlsxwriter

ROW_TEMPLATE = [
  'Registry', 'Image Name', 'Vulnerability Name', 'Vendor CVSS v2 Severity', 'Vendor CVSS v2 Score',
  'NVD CVSS v2 Severity', 'NVD CVSS v2 Score', 'Resource', 'Resource Type', 'Installed Version',
  'Publish Date', 'Fix Version', 'Solution', 'Image Digest', 'Referenced By', 'Vendor CVSS v3 Vectors',
  'Vendor URL', 'NVD CVSS v2 Vectors', 'NVD URL', 'Qualys IDs', 'Description', 'Applied By',
  'Applied On', 'Reverted By', 'Reverted On', 'Enforced By', 'Enforced On', 'vShield Status',
  'Acknowledged Date', 'Base Image Vulnerability', 'Base Image Name'
]

def craftSink(path_):
  """ Opens a reference to an Excel WorkBook and Worksheet objects """
  b = xlsxwriter.Workbook(path_)
  s = b.add_worksheet("Sheet 1")
  f = b.add_format({'bold': True})

  """ Write the header line into the worksheet """
  for i, c in enumerate(ROW_TEMPLATE, start=0):
    s.write_string(0, i, c, f)
    s.set_column(i, i, len(c) + 5)

  s.freeze_panes(1, 0)

  return b, s

def addVulnerability(data_, sink_, lineno_):
  for i, c in enumerate(ROW_TEMPLATE, start=0):
    sink_.write_string(lineno_, i, str(data_[c]) if c in data_ else ' ')

  return lineno_ + 1

def addVulnerabilities(source_, builder_):
  with open(source_) as f:
    d = json.load(f)
    if not 'resources' in d.keys():
        return
    for r in filter(lambda r_: 'vulnerabilities' in r_,  d['resources']):
      for v in r['vulnerabilities']:
        x = {}
        x['Registry'], y = d['metadata']['repo_digests'][0].split('/', 1)
        x['Image Name'], x['Image Digest'] = y.split('@', 1)
        R = r['resource']
        if 'format' in R:
          x['Resource'] = R['name']
          x['Resource Type'] = R['format']
          x['Installed Version'] = R['version']
        elif 'type' in R:
          x['Resource'] = R['path']
          x['Resource Type'] = 'file'

        x['Vulnerability Name'] = v['name']
        x['Vendor CVSS v2 Severity'] = v['vendor_severity']
        s = 7 > float(v['vendor_score'])
        x['Vendor CVSS v2 Score'] = v['vendor_score']
        if 'nvd_severity' in v:
          x['NVD CVSS v2 Severity'] = v['nvd_severity']
        if 'nvd_score' in v:
          s = s and 7 > float(v['nvd_score'])
          x['NVD CVSS v2 Score'] = v['nvd_score']
        if 'fix_version' in v:
          x['Fix Version'] = v['fix_version']
        if 'solution' in v:
          x['Solution'] = v['solution']
        if 'publish_date' in v:
          x['Publish Date'] = v['publish_date']
        if 'vendor_vectors_v3' in v:
          x['Vendor CVSS v3 Vectors'] = v['vendor_vectors_v3']
        if 'vendor_url' in v:
          x['Vendor URL'] = v['vendor_url']
        if 'nvd_vectors' in v:
          x['NVD CVSS v2 Vectors'] = v['nvd_vectors']
        if 'nvd_url' in v:
          x['NVD URL'] = v['nvd_url']
        if 'description' in v:
          x['Description'] = v['description']

        x['Base Image Vulnerability'] = 'FALSE'
        if not s:
          builder_(x)

def direct(silo_, builder_):
  for f in os.listdir(silo_):
    if f.endswith(".json"):
      addVulnerabilities('%s/%s' % (silo_, f), builder_)

def main():
  d, x = None, None
  try:
    O, A = getopt.getopt(sys.argv[1:], 'i:o:')
    for o, a in O:
      if '-i' == o:
        d = a
      elif '-o' == o:
        x = a

  except getopt.GetoptError as error_:
    print >> sys.stderr, str(error_)
    sys.exit(1)

  if not(d and x):
    print >> sys.stderr, "Both -i and -o values are mandatory"
    sys.exit(2)

  b, s = craftSink(x)
  l = [1]
  def build(report_):
    l[0] = addVulnerability(report_, s, l[0])

  direct(d, build)
  s.autofilter(0, 0, l[0] - 1, len(ROW_TEMPLATE) - 1)
  b.close()

if __name__ == "__main__":
  main()
