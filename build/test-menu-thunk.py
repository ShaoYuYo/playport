#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile complete production menu thunks, mocking only the native menu API."""
from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parent.parent;t=Path(sys.argv[1]);out=r/'.work/menu-thunk-test';out.mkdir(parents=True,exist_ok=True)
user=(t/'dlls/wow64win/user.c').read_text();private=(t/'dlls/wow64win/wow64win_private.h').read_text()
def function(text,signature):
 a=text.index(signature);b=text.index('\n}',a)+2;return text[a:b]+'\n'
structs=user[user.index('typedef struct\n{'):user.index('} MENUITEMINFOW32;')+len('} MENUITEMINFOW32;')]
helpers=''.join(function(private,s) for s in ['static inline void *wow64_to_host(', 'static inline ULONG wow64_to_guest(', 'static inline void *wow64_intres_to_host(', 'static inline UNICODE_STRING *unicode_str_32to64('])
prefix=r'''
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
typedef uint32_t UINT,ULONG,UINT32,DWORD;
typedef uint64_t ULONG64;
typedef uintptr_t ULONG_PTR,UINT_PTR;
typedef int32_t NTSTATUS;
typedef uint16_t WCHAR;
typedef void *HMENU,*HBITMAP,*HBRUSH,*HWND;
typedef int32_t LONG,BOOL;
typedef struct {LONG left,top,right,bottom;} RECT;
typedef struct {DWORD cbSize;RECT rcBar;HMENU hMenu;HWND hwndMenu;BOOL fBarFocused:1;BOOL fFocused:1;} MENUBARINFO;
#define TRUE 1
#define FALSE 0
#define ERROR_INVALID_PARAMETER 87
static int last_error;
static void set_last_error32(int error){last_error=error;}
typedef struct { uint16_t Length,MaximumLength; WCHAR *Buffer; } UNICODE_STRING;
typedef struct { uint16_t Length,MaximumLength; ULONG Buffer; } UNICODE_STRING32;
typedef struct { UINT cbSize,fMask,fType,fState,wID; HMENU hSubMenu; HBITMAP hbmpChecked,hbmpUnchecked;
 ULONG_PTR dwItemData; WCHAR *dwTypeData; UINT cch; HBITMAP hbmpItem; } MENUITEMINFOW;
typedef struct { DWORD cbSize,fMask,dwStyle;UINT cyMax;HBRUSH hbrBack;DWORD dwContextHelpID;ULONG_PTR dwMenuData; } MENUINFO;
#define WINAPI
#define ULongToPtr(x) ((void *)(uintptr_t)(uint32_t)(x))
#define UlongToPtr(x) ULongToPtr(x)
#define PtrToUlong(x) ((ULONG)(uintptr_t)(x))
#define UlongToHandle(x) ULongToPtr(x)
#define LongToHandle(x) ((void *)(intptr_t)(int32_t)(x))
#define HandleToUlong(x) PtrToUlong(x)
#define ERR(...) fprintf(stderr,__VA_ARGS__)
#define MIIM_STATE 1
#define MIIM_ID 2
#define MIIM_SUBMENU 4
#define MIIM_CHECKMARKS 8
#define MIIM_TYPE 16
#define MIIM_DATA 32
#define MIIM_STRING 64
#define MIIM_BITMAP 128
#define MIIM_FTYPE 256
#define MFT_BITMAP 4
#define MFT_OWNERDRAW 256
enum { NtUserSetMenuItemInfo,NtUserInsertMenuItem,NtUserCheckMenuRadioItem,NtUserGetMenuDefaultItem,
 NtUserGetMenuItemID,NtUserGetMenuItemInfoA,NtUserGetMenuItemInfoW,NtUserGetMenuState,NtUserGetSubMenu };
static ULONG64 wow64_window_base;
static int rejected,scenario;
static ULONG wow64_guest_rejected(const void *p){(void)p;rejected++;return 0;}
static _Alignas(16) unsigned char arena[16384];
static WCHAR *text_buffer;
static ULONG get_ulong(UINT **args){return *(*args)++;}
'''
middle=r'''
static void *get_ptr(UINT **args){return wow64_to_host(get_ulong(args));}
static void *get_handle(UINT **args){return LongToHandle(get_ulong(args));}
static UINT NtUserThunkedMenuItemInfo(HMENU menu,UINT pos,UINT flags,UINT method,MENUITEMINFOW *info,UNICODE_STRING *str){
 assert(menu==(void *)0x10054 && pos==UINT32_MAX && flags==0x400);
 if(scenario==1){
  assert(method==NtUserInsertMenuItem && info && info->dwTypeData==text_buffer);
  assert(info->dwItemData==0xf1234567 && info->hSubMenu==(void *)0x1234);
  assert(info->hbmpItem==(void *)(intptr_t)-1);
  assert(str && str->Buffer==text_buffer && str->Length==4);return 42;
 }
 if(scenario==2){assert(method==NtUserSetMenuItemInfo && (uintptr_t)info->dwTypeData==0xf1234567);return 42;}
 if(scenario==3){assert((uintptr_t)info->dwTypeData==0x3142);return 42;}
 if(scenario==4 || scenario==5){
  assert(info->dwTypeData==text_buffer && info->cch==8);
  if(scenario==4){assert(method==NtUserGetMenuItemInfoW);text_buffer[0]='A';text_buffer[1]=0;}
  else {assert(method==NtUserGetMenuItemInfoA);((char *)text_buffer)[0]='A';((char *)text_buffer)[1]=0;}
  info->cch=1;info->dwItemData=0xf7654321;return 77;
 }
 if(scenario==6){info->fType=MFT_BITMAP;info->dwTypeData=(void *)0x3344;info->hbmpItem=(void *)0x3344;info->cch=0;return 77;}
 if(scenario==7){info->fType=MFT_OWNERDRAW;info->dwTypeData=NULL;info->cch=0;return 77;}
 if(scenario==8){assert(!info && !str && (method==NtUserGetSubMenu || method==NtUserGetMenuDefaultItem || method==NtUserGetMenuItemID || method==NtUserGetMenuState));return 0x11234;}
 if(scenario==9){assert(method==NtUserCheckMenuRadioItem && info->cch==25 && info->fMask==10);return 1;}
 assert(0);return 0;
}
static UINT NtUserThunkedMenuInfo(HMENU menu,MENUINFO *info){
 assert(menu==(void *)0x10054);
 if(!info)return 0;
 assert(info->cbSize==sizeof(*info) && info->fMask==0x10 && info->dwStyle==3);
 assert(info->hbrBack==(void *)0x1224 && info->dwMenuData==0xf1234567);return 1;
}
static UINT NtUserGetMenuBarInfo(HWND hwnd,LONG id,LONG item,MENUBARINFO *info){
 assert(hwnd==(void *)0x10054 && id==-3 && item==2 && info->cbSize==sizeof(*info));
 info->rcBar=(RECT){1,2,30,40};info->hMenu=(void *)0x2233;info->hwndMenu=(void *)0x3344;
 info->fBarFocused=-1;info->fFocused=0;return 1;
}
'''
suffix=r'''
int main(void){
 struct rlimit core={0,0};assert(!setrlimit(RLIMIT_CORE,&core));
 MENUITEMINFOW32 *info=(void *)arena;
 UNICODE_STRING32 *str=(void *)(arena+4096);
 text_buffer=(void *)(arena+8192);
 wow64_window_base=(uintptr_t)arena-0x100000;
 assert(wow64_window_base>UINT32_MAX);
 UINT args[]={0x10054,UINT32_MAX,0x400,NtUserInsertMenuItem,0x100000,0x101000};
 info->cbSize=sizeof(*info);info->fMask=MIIM_STRING|MIIM_DATA|MIIM_SUBMENU;
 info->dwTypeData=0x102000;info->dwItemData=0xf1234567;info->hSubMenu=0x1234;info->hbmpItem=UINT32_MAX;
 str->Length=4;str->MaximumLength=6;str->Buffer=0x102000;
 scenario=1;assert(wow64_NtUserThunkedMenuItemInfo(args)==42);
 args[5]=0;args[3]=NtUserSetMenuItemInfo;info->fMask=MIIM_TYPE;info->fType=MFT_OWNERDRAW;info->dwTypeData=0xf1234567;
 scenario=2;assert(wow64_NtUserThunkedMenuItemInfo(args)==42);
 info->fType=MFT_BITMAP;info->dwTypeData=0x3142;scenario=3;assert(wow64_NtUserThunkedMenuItemInfo(args)==42);
 for(scenario=4;scenario<=7;scenario++){
  args[3]=scenario==5 ? NtUserGetMenuItemInfoA:NtUserGetMenuItemInfoW;
  info->fMask=scenario>=6 ? MIIM_TYPE:MIIM_STRING|MIIM_DATA;
  info->dwTypeData=0x102000;info->cch=8;
  assert(wow64_NtUserThunkedMenuItemInfo(args)==77);
  assert(info->dwTypeData==(scenario==6 ? 0x3344:scenario==7 ? 0:0x102000));
  if(scenario<=5){assert(info->dwItemData==0xf7654321 && info->cch==1);}
 }
 scenario=8;args[3]=NtUserGetSubMenu;args[4]=0;assert(wow64_NtUserThunkedMenuItemInfo(args)==0x11234);
 const UINT scalar_methods[]={NtUserGetMenuDefaultItem,NtUserGetMenuItemID,NtUserGetMenuState};
 for(unsigned i=0;i<sizeof(scalar_methods)/sizeof(scalar_methods[0]);i++){
  args[3]=scalar_methods[i];assert(wow64_NtUserThunkedMenuItemInfo(args)==0x11234);
 }
 scenario=9;args[3]=NtUserCheckMenuRadioItem;args[4]=0x100000;info->fMask=10;info->cch=25;
 assert(wow64_NtUserThunkedMenuItemInfo(args)==1);
 MENUINFO32 *menu=(void *)arena;memset(menu,0,sizeof(*menu));menu->cbSize=sizeof(*menu);menu->fMask=0x10;
 menu->dwStyle=3;menu->hbrBack=0x1224;menu->dwMenuData=0xf1234567;
 UINT menu_args[]={0x10054,0x100000};assert(wow64_NtUserThunkedMenuInfo(menu_args)==1);
 menu_args[1]=0;assert(!wow64_NtUserThunkedMenuInfo(menu_args));
 struct {DWORD cbSize;RECT rcBar;ULONG hMenu,hwndMenu;BOOL fBarFocused:1;BOOL fFocused:1;} *bar=(void *)arena;
 bar->cbSize=sizeof(*bar);UINT bar_args[]={0x10054,(UINT)-3,2,0x100000};
 assert(wow64_NtUserGetMenuBarInfo(bar_args));
 assert(bar->hMenu==0x2233 && bar->hwndMenu==0x3344 && bar->rcBar.bottom==40 && bar->fBarFocused && !bar->fFocused);
 bar->cbSize=1;assert(!wow64_NtUserGetMenuBarInfo(bar_args) && last_error==87);
 assert(!rejected);
 wow64_window_base=0;scenario=8;args[3]=NtUserGetSubMenu;args[4]=0;assert(wow64_NtUserThunkedMenuItemInfo(args)==0x11234);
 puts("Production menu thunks: insert/set, A/W get, bitmap/sentinel, opaque data, scalar methods and menu info pass");
}
'''
fix=subprocess.check_output(['git','-C',str(t),'log','-1','--format=%H',
                             '--grep=^wow64win: convert menu item strings through the guest window$',
                             '--','dlls/wow64win/user.c']).decode().strip()
if not fix:raise RuntimeError('menu conversion patch is absent from this source history')
before=subprocess.check_output(['git','-C',str(t),'show',fix+'^:dlls/wow64win/user.c']).decode()
for label,text,success in [('after',user,True),('before',before,False)]:
 code=prefix+structs+'\n'+(t/'dlls/wow64/wow64_window.h').read_text()+'\n'+helpers+middle+function(text,'NTSTATUS WINAPI wow64_NtUserThunkedMenuItemInfo(')+function(text,'NTSTATUS WINAPI wow64_NtUserThunkedMenuInfo(')+function(text,'NTSTATUS WINAPI wow64_NtUserGetMenuBarInfo(')+suffix
 p=out/(label+'.c');p.write_text(code);exe=out/label
 subprocess.run(['clang','-std=c11','-O1','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-missing-field-initializers','-fsanitize=undefined','-fno-sanitize-recover=all',str(p),'-o',str(exe)],check=True)
 run=subprocess.run([str(exe)],capture_output=True,text=True);(out/(label+'.log')).write_text(run.stdout+run.stderr)
 if success and run.returncode:raise RuntimeError(run.stdout+run.stderr)
 if not success and run.returncode!=-6:raise RuntimeError('old thunk did not reproduce the nested-pointer assertion')
 print(label,run.stdout.strip() if success else 'original nested string pointer fails production-thunk assertion')
header=(t/'dlls/wow64win/window_audited.h').read_text()
assert '#define WINDOW_AUDITED_NtUserThunkedMenuItemInfo ~, 1' in header
assert '#define WINDOW_AUDITED_NtUserThunkedMenuInfo ~, 1' in header
assert '#define WINDOW_AUDITED_NtUserGetMenuBarInfo ~, 1' in header
