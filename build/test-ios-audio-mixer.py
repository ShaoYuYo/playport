#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the actual iOS mixer against deterministic rings, without AudioUnit."""
import argparse,resource,subprocess,tempfile
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('tree',type=Path);args=p.parse_args()
text=(args.tree/'build/ntdll-unix/audio_null_ios.c').read_text()
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
scratch=repo/'.work';scratch.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='audio-mixer-',dir=scratch) as work:
    root=Path(work)
    before=subprocess.check_output(['git','-C',str(args.tree),'show','HEAD^:build/ntdll-unix/audio_null_ios.c']).decode()
    for name,code in [('before',before),('after',text)]:
        start=code.index('static void ios_mix_stream(')
        end=code.index('/* Core Audio real-time thread. See ios_mix_stream',start)
        (root/'actual_mixer.h').write_text(code[start:end]);exe=root/name
        subprocess.run(['clang','-std=c11','-O2','-g','-Wall','-Wextra','-Werror',
            '-fsanitize=address,undefined','-fno-sanitize-recover=all','-I',str(root),
            str(repo/'build/tests/audio_mixer_test.c'),'-lm','-o',str(exe)],check=True)
        result=subprocess.run([str(exe)]+(['phase'] if name=='before' else []),cwd=root,capture_output=True,text=True)
        if name=='before':
            if not result.returncode or 'Assertion' not in result.stderr:raise RuntimeError('baseline did not reproduce phase drift: '+result.stderr)
            print('Baseline reproduces callback-partition-dependent sample consumption')
        elif result.returncode:raise RuntimeError(result.stderr)
        else:print(result.stdout.strip())
