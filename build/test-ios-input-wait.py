#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the actual wait_message and timeout conversion against mock wait APIs."""
from pathlib import Path
import argparse,resource,subprocess,tempfile
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
repo=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('tree',type=Path)
args=parser.parse_args();path='build/win32u-unix/message_ios.c'
def function(text,name):
    pos=text.index('static ',text.rfind('\n',0,text.index(name+'('))+1)
    brace=text.index('{',pos);end=brace+1;depth=1
    while depth:
        depth += {'{':1,'}':-1}.get(text[end],0);end+=1
    return text[pos:end]+'\n'
scratch=repo/'.work';scratch.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='input-wait-',dir=scratch) as work:
    root=Path(work)
    current=(args.tree/path).read_text()
    baseline=subprocess.check_output(['git','-C',str(args.tree),'show','HEAD^:'+path]).decode()
    for name,text in [('before',baseline),('after',current)]:
        (root/'actual_wait.h').write_text(function(text,'get_nt_timeout')+function(text,'wait_message'))
        exe=root/name
        subprocess.run(['clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror',
            '-Wno-unused-function','-Wno-unused-variable','-Wno-incompatible-pointer-types',
            '-fsanitize=address,undefined','-fno-sanitize-recover=all','-I',str(root),
            str(repo/'build/tests/input_wait_test.c'),'-o',str(exe)],check=True)
        result=subprocess.run([str(exe)],cwd=root,capture_output=True,text=True)
        if name=='before':
            if not result.returncode:raise RuntimeError('baseline unexpectedly passed')
            if 'Assertion' not in result.stderr:raise RuntimeError(result.stderr)
            print('Baseline reproduces delayed/missed driver input during game waits')
        else:
            if result.returncode:raise RuntimeError(result.stderr)
            print(result.stdout.strip())
