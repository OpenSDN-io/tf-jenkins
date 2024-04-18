#!/usr/bin/env python3

import os
import sys
import excel
import getopt

def craftWhitelist(source_):
  output = set()
  with open(source_, 'r') as f:
    for l in f:
      output.add(l.strip())

  return output

def main():
  d, w, x = None, None, None
  try:
    O, A = getopt.getopt(sys.argv[1:], 'i:o:w:')
    for o, a in O:
      if '-i' == o:
        d = a
      elif '-o' == o:
        x = a
      elif '-w' == o:
        w = a

  except getopt.GetoptError as error_:
    print >> sys.stderr, str(error_)
    sys.exit(1)

  if not(d and w and x):
    print >> sys.stderr, "Both -i and -o and -w values are mandatory"
    sys.exit(2)

  B = []
  W = craftWhitelist(w)
  def estimate(report_):
    if report_['Vulnerability Name'] not in W:
      B.append(report_)

  excel.direct(d, estimate)
  if 0 < len(B):
    b, s = excel.craftSink(x)
    l = 1
    for r in B:
      l = excel.addVulnerability(r, s, l)

    s.autofilter(0, 0, l - 1, len(excel.ROW_TEMPLATE) - 1)
    b.close()

if __name__ == "__main__":
  main()

