#!/bin/sh
#Create a patch for modified yavdb installed in ~/.vim/bundle against
#original in ~/vim.

mv ../../yavdb/plugin/yavdb.vim ../../yavdb
mv ../../yavdb/doc/yavdb.txt ../../yavdb
if [ -e ../../yavdb/doc/tags ]; then
    rm ../../yavdb/doc/tags
fi
rmdir ../../yavdb/doc ../../yavdb/plugin

diff -Naur ~/vim/yavdb ../../yavdb/ > ./yavdb.diff

mkdir -p ../../yavdb/plugin ../../yavdb/doc
mv ../../yavdb/yavdb.vim ../../yavdb/plugin
mv ../../yavdb/yavdb.txt ../../yavdb/doc

