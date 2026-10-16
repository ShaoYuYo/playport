#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Losslessly deflate the IPA container and verify every entry before replacing it.

The extracted bundle (including signatures) stays byte-for-byte identical.
Installed app size is unchanged; transfer/archive size is reduced.
"""
import copy
import hashlib
from pathlib import Path
import sys
import zipfile


def inventory(path):
    with zipfile.ZipFile(path) as z:
        rows=[]
        for info in z.infolist():
            with z.open(info) as f:
                digest=hashlib.file_digest(f,'sha256').hexdigest()
            rows.append((info.filename,info.file_size,digest,info.external_attr,
                         info.create_system,info.date_time,info.comment,info.extra))
        return z.comment,rows


def compress(path):
    path=path.resolve()
    temporary=path.with_name(path.name+'.deflate-candidate')
    if temporary.exists():
        raise ValueError('compression candidate already exists')
    before=path.stat().st_size
    try:
        with zipfile.ZipFile(path) as source, zipfile.ZipFile(temporary,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as dest:
            dest.comment=source.comment
            for info in source.infolist():
                cloned=copy.copy(info)
                cloned.compress_type=zipfile.ZIP_STORED if info.is_dir() else zipfile.ZIP_DEFLATED
                cloned._compresslevel=6
                with source.open(info) as src,dest.open(cloned,'w',force_zip64=info.file_size>=2**31) as target:
                    while chunk:=src.read(1024*1024):
                        target.write(chunk)
        if inventory(path)!=inventory(temporary):
            raise ValueError('compressed bundle content or metadata changed')
        after=temporary.stat().st_size
        if after<before:
            temporary.replace(path)
        else:
            after=before
        print(f'IPA lossless compression: {before:,} -> {after:,} bytes; all entry hashes and permissions retained')
    finally:
        temporary.unlink(missing_ok=True)


if __name__=='__main__':
    compress(Path(sys.argv[1]))
