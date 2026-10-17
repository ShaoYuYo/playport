#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise actual bounded save-open classifier; no game data required."""
import subprocess,sys,tempfile
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
code=(Path(sys.argv[1])/'build/ntdll-unix/server_ios.c').read_text()
start=code.index('static const char *ios_save_open_probe(')
end=code.index('/***********************************************************************',start)
with tempfile.TemporaryDirectory(prefix='save-probe-',dir=repo/'.work') as directory:
    root=Path(directory)
    (root/'probe.c').write_text('''#include <assert.h>
#include <string.h>
#include <stdio.h>
'''+code[start:end]+'''
int main(void) {
    const char *backend=NULL;
    const char *paths[]={"/prefix/GSE Saves/1144400/remote/DATASU.KSD",
        "/prefix/YuzuSoft/SenrenBanka/datasc.ksd", "/another/savecheck", "data_anchor.ksd"};
    const char *names[]={"datasu.ksd","datasc.ksd","savecheck","data_anchor.ksd"};
    const char *tags[]={"steam","native","other","other"};
    for(unsigned i=0;i<4;i++) {
        assert(!strcmp(ios_save_open_probe(paths[i],strlen(paths[i]),&backend),names[i]));
        assert(!strcmp(backend,tags[i]));
    }
    char bounded[]={'d','a','t','a','s','u','.','k','s','d'};
    assert(!strcmp(ios_save_open_probe(bounded,sizeof(bounded),&backend),"datasu.ksd"));
    assert(!ios_save_open_probe("ticket=secret",13,&backend));
    assert(!ios_save_open_probe("datasu.ksd.private",18,&backend));
    assert(!ios_save_open_probe("datasu.ksd\\0private",18,&backend));
    assert(!ios_save_open_probe(bounded,2048,&backend));
    assert(!ios_save_open_probe(NULL,10,&backend));
    assert(!ios_save_open_probe(bounded,0,&backend));
    puts("Save-open classifier: exact fixed names, mixed case, non-NUL slices, bounds and privacy passed");
}
''')
    exe=root/'probe'
    subprocess.run(['clang','-O2','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(root/'probe.c'),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
