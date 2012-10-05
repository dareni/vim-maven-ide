#!/bin/sh
#Apply the patch to yavdb installed in ~/.vim/bundle.

patch -d ../../yavdb < ./yavdb.diff
mkdir -p ../../yavdb/plugin ../../yavdb/doc
mv ../../yavdb/yavdb.vim ../../yavdb/plugin
mv ../../yavdb/yavdb.txt ../../yavdb/doc
