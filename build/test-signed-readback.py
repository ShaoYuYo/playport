#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the complete production readback helper against real Win32 APIs.

Run the generated console executable on Windows; no game, window or phone is
launched by the executable. Scratch files stay beside the test executable.
"""
from pathlib import Path
import os,subprocess,sys
r=Path(__file__).resolve().parent.parent
wine=Path(sys.argv[1]);out=r/'.work/signed-readback-test';out.mkdir(parents=True,exist_ok=True)
text=(wine/'dlls/kernelbase/file.c').read_text()
a=text.index('static void playport_original_readback(');b=text.index('\n}',a)+2
helper=text[a:b]
prefix=r'''
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <wchar.h>
#include <assert.h>
#define ARRAY_SIZE(x) (sizeof(x)/sizeof((x)[0]))
#define wcsnicmp _wcsnicmp
#define ERR(...) ((void)0)
NTSYSAPI BOOLEAN NTAPI RtlCreateUnicodeString(UNICODE_STRING *,PCWSTR);
'''
main=r'''
static void check(const WCHAR *name,DWORD access,DWORD creation,DWORD flags,int redirected)
{
 UNICODE_STRING n;WCHAR expected[2048];
 wcscpy(expected,L"\\??\\");wcscat(expected,name);if(redirected)wcscat(expected,L".orig");
 {WCHAR nt[2048];wcscpy(nt,L"\\??\\");wcscat(nt,name);assert(RtlCreateUnicodeString(&n,nt));}
 SetLastError(1234);playport_original_readback(&n,access,creation,flags);
 assert(!wcscmp(n.Buffer,expected));assert(GetLastError()==1234);RtlFreeUnicodeString(&n);
}
int main(void)
{
 WCHAR exe[2048],file[2048],orig[2048],other[2048],env[8192];DWORD n;
 HANDLE h;const char bytes[]="publisher-original";char readback[64]={0};DWORD got;
 UNICODE_STRING name;
 n=GetModuleFileNameW(NULL,exe,ARRAY_SIZE(exe));assert(n && n<ARRAY_SIZE(exe));
 *wcsrchr(exe,'\\')=0;wcscpy(file,exe);wcscat(file,L"\\fixture.exe");
 wcscpy(orig,file);wcscat(orig,L".orig");wcscpy(other,file);wcscat(other,L".different");
 h=CreateFileW(orig,GENERIC_WRITE,0,NULL,CREATE_ALWAYS,0,NULL);assert(h!=INVALID_HANDLE_VALUE);
 assert(WriteFile(h,bytes,sizeof(bytes),&got,NULL));CloseHandle(h);
 SetEnvironmentVariableW(L"PLAYPORT_ORIGINAL_READBACK",file);
 check(file,GENERIC_READ,OPEN_EXISTING,0,1);
 check(file,FILE_READ_DATA|SYNCHRONIZE,OPEN_EXISTING,0,1);
 check(other,GENERIC_READ,OPEN_EXISTING,0,0);
 check(file,GENERIC_READ|GENERIC_WRITE,OPEN_EXISTING,0,0);
 check(file,GENERIC_READ|GENERIC_EXECUTE,OPEN_EXISTING,0,0);
 check(file,GENERIC_READ|DELETE,OPEN_EXISTING,0,0);
 check(file,GENERIC_READ,CREATE_ALWAYS,0,0);
 check(file,GENERIC_READ,OPEN_ALWAYS,0,0);
 check(file,GENERIC_READ,OPEN_EXISTING,FILE_FLAG_DELETE_ON_CLOSE,0);
 check(file,GENERIC_READ,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
 wcscpy(env,other);wcscat(env,L"\n");wcscat(env,file);SetEnvironmentVariableW(L"PLAYPORT_ORIGINAL_READBACK",env);
 check(file,GENERIC_READ,OPEN_EXISTING,0,1);
 check(other,GENERIC_READ,OPEN_EXISTING,0,0); /* allowlisted but missing original */
 {WCHAR nt[2048];wcscpy(nt,L"\\??\\");wcscat(nt,file);assert(RtlCreateUnicodeString(&name,nt));}
 playport_original_readback(&name,GENERIC_READ,OPEN_EXISTING,0);
 h=CreateFileW(name.Buffer+4,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,0,NULL);
 assert(h!=INVALID_HANDLE_VALUE);assert(ReadFile(h,readback,sizeof(readback),&got,NULL));
 assert(got==sizeof(bytes)&&!memcmp(readback,bytes,sizeof(bytes)));CloseHandle(h);RtlFreeUnicodeString(&name);
 SetEnvironmentVariableW(L"PLAYPORT_ORIGINAL_READBACK",NULL);check(file,GENERIC_READ,OPEN_EXISTING,0,0);
 DeleteFileW(orig);puts("signed-readback: 14 cases passed; real original bytes read; last-error preserved");return 0;
}
'''
(out/'test.c').write_text(prefix+helper+main)
compiler=Path(os.environ['LLVM_MINGW'])/'bin/i686-w64-mingw32-clang'
subprocess.run([str(compiler),'-Wall','-Wextra','-Werror',str(out/'test.c'),'-lntdll','-o',str(out/'test.exe')],check=True)
print('Built Win32 production-helper test:',out/'test.exe')
