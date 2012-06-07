vim-maven-ide
=============

A maven plugin for vim.

Features include:
o Project tree for file navigation and environment context management.\
o Quickfix for output of maven plugins compile,junit,checkstyle. 
o Optional single source file compilation directly with javac.
o Compilation is background via AsyncCommand.
o Debug using yavdb, allows debug of class main or attach to jvm debug port.
o Junit run/quickfix/debug.                   
o Dependency source file and javadoc integration. Javadoc viewing uses lynx.                                       
o Exctags tag navigation. 
o Auto generation of project environment ie classpath, tag files.
o Dependency management for maven parent/child/sibling projects extracted from project poms.                          
o Autocomplete on methods, auto add of imports etc is via the vjde plugin project.

See doc/maven-ide.txt for more detail.