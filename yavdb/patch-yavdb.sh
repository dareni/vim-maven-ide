#!/bin/sh
#Apply the patch to yavdb installed in ~/.vim/bundle.

CPATH=`pwd`
if [ "${CPATH##*/}" != "yavdb" ]; then
    echo "Must execute patch-yavdb.sh from the maven-ide/yavdb dir."
    exit;
fi

patch -d ../../yavdb < ./yavdb.diff
mkdir -p ../../yavdb/plugin ../../yavdb/doc
mv ../../yavdb/yavdb.vim ../../yavdb/plugin
mv ../../yavdb/yavdb.txt ../../yavdb/doc
