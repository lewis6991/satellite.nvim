#!/usr/bin/env python3

import glob
import os
from string import Template
import subprocess
import sys
import tempfile

test_dir = os.path.dirname(os.path.realpath(__file__))
project_dir = os.path.join(test_dir, os.path.pardir)
test_scripts = sorted(glob.glob(os.path.join(test_dir, 'test_*.vim')))
errors = []
template = Template("""
try
  source ${file}
catch
  call assert_report(v:throwpoint . ': ' . v:exception)
endtry
verbose echo join(v:errors, "\\n")
quitall!
""")
for test_script in test_scripts:
    with tempfile.TemporaryDirectory() as tmp:
        runner_script = os.path.join(tmp, 'runner.vim')
        with open(runner_script, 'w') as f:
            f.write(template.substitute(
                project_dir=project_dir, file=test_script))
        args = [
            'nvim',
            '-n',  # no swap file
            '-e',  # start in Ex mode
            '-s',  # silent mode
            '-S', runner_script,  # source the test runner script
        ]
        result = subprocess.run(args, capture_output=True)
    lines = result.stderr.decode('ascii').splitlines()
    lines = [line.strip() for line in lines]
    lines = [line for line in lines if line]
    for line in lines:
        print(line, file=sys.stderr)
    errors.extend(lines)
sys.exit(min(len(errors), 255))
