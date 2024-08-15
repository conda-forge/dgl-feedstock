#!/usr/bin/env python

"""Script to update vendored downloads for dgl-feedstock.

This script expects to be called from a clone of the upstream dgl repo
with the desired commit checked out, usually the relevant version tag.
"""

from textwrap import dedent, indent
from urllib.request import urlopen
from hashlib import sha256

from git import Repo

MB = 1024 * 1024

repo = Repo(".")

devendored_projects = [
    "dmlc-core",
    "dlpack",
    # "googletest",
    "METIS",
    "phmap",
    "nanoflann",
    #"libxsmm",
    #"pcg",
    #"cccl",
    "liburing",
    #"cuco",
]

for sm in repo.submodules:
    project = sm.name.removeprefix("third_party/")
    if project in devendored_projects:
        continue
    url = f"{sm.url.removesuffix('.git')}/archive/{sm.hexsha}.tar.gz"
    m = sha256()
    with urlopen(url) as f:
        while chunk := f.read(5 * MB):
            m.update(chunk)
    print(indent(dedent(f"""\
          - url: {url}
            sha256: {m.hexdigest()}
            path: {sm.name}
            """), "  "))
