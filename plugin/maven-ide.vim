"=============================================================================
" File:        maven-ide.vim
" Author:      Daren Isaacs (ikkyisaacs at gmail.com)
" Last Change: Fri Aug 17 22:02:35 EST 2012
" Version:     0.5
"=============================================================================
" See documentation in accompanying help file.
" You may use this code in whatever way you see fit.

"{{{ Project ------------------------------------------------------------------
function! MvnGetProjectDirList(projectCount, excludeSubProjects) "{{{
"Build a list of project directories from the 'project' buffer starting
"   under the cursor. Used to build the environment file in.vim.
"projectCount - the number of parent projects directories to return. -1 return all
"   projects from the cursor to the end.
"excludeSubProjects - set 1 to return only top level projects,
"    0 includes subprojects.
"return - a list of project directories.
"{{{ body
    let l:projectDirList = []
    let l:save_cursor = getpos('.')
    let l:finish = 0
    let l:counter = 0
    let l:projectCount = a:projectCount
    let l:prjRegExp = "^\\s*.\\+in=in.vim"
    if a:excludeSubProjects
        let l:prjRegExp = "^\\S.\\+in=in.vim"
    endif
    if strlen(l:projectCount) == 0
        call inputsave()
        let l:projectCount = input("Enter the project count [empty: all".
        \" projects from cursor to file end]:")
        call inputrestore()
    endif
    if strlen(l:projectCount) == 0
        let l:projectCount = -1
    endif

    let l:projectDir = MvnGetProjectDir(l:save_cursor[1])
    if !strlen(l:projectDir) > 0
        echo("Error - Current line is not a project header!")
        return l:projectDirList
    endif
    let l:onlyCountParents = 1
    if 0 == match(getline(l:save_cursor[1]), "^\\s")
        let l:onlyCountParents = 0
    endif

    while !l:finish
        let l:projectLineNo = search(l:prjRegExp, 'Wc')
        if l:projectLineNo == 0
            let l:finish = 1
        else
            let l:projectDir = MvnGetProjectDir(l:projectLineNo)
            if strlen(l:projectDir) > 0
                if !l:onlyCountParents
                    let l:counter += 1 "counting child and parents
                elseif -1 == match(getline(l:projectLineNo), "^\\s")
                    let l:counter += 1 "is a parent
                endif
                if l:counter > l:projectCount && l:projectCount != -1
                    let l:finish = 1
                else
                    call add(l:projectDirList, l:projectDir)
                endif
            endif
            call cursor(l:projectLineNo + 1, l:save_cursor[2])
        endif
    endwhile
    call setpos('.', l:save_cursor)
    return l:projectDirList
endfunction; "}}} body }}}

function! MvnGetProjectDir(projectLineNo) "{{{
"Get the project directory from the project config file using the given
"   line number.
"{{{ body
    let l:line = getline(a:projectLineNo)
    let l:projectDir = matchstr(l:line, '=\@<=\([/A-Za-z0-9._-]\+\)', 0, 1)
    if strlen(l:projectDir) > 0 && filereadable(l:projectDir."/pom.xml")
        return l:projectDir
    endif
    return ""
endfunction; "}}} body }}}

function! MvnInsertProjectTree(projPath) "{{{
"Build the project tree text for a maven project.
"a:projPath - non empty string turns off the prompt for unit test.
    let l:prjIdPomFilename = MvnGetPrjIdPomFilename()
    if strlen(a:projPath) > 0
        let l:mvnProjectPath= a:projPath
    else
        if strlen(s:mvn_defaultProject) == 0
            let s:mvn_defaultProject = matchstr(system("pwd"), "\\p\\+")
        endif
        call inputsave()
        let l:mvnProjectPath = input("Enter the maven project path:", s:mvn_defaultProject)
        call inputrestore()
    endif
    call inputsave()
    let l:mvnProjectPath = input("Enter the maven project path:", s:mvn_defaultProject, "file")
    call inputrestore()
    if !isdirectory(l:mvnProjectPath)
        echo("Invalid Directory: ".l:mvnProjectPath)
        return
    endif
    let l:specificProject = 0
    if filereadable(l:mvnProjectPath."/pom.xml")
        let l:specificProject = 1
    endif
    let s:mvn_defaultProject = l:mvnProjectPath

    let l:cmd = "find ".l:mvnProjectPath." -name pom.xml -print"
    let l:pomList = split(system(l:cmd))
    call sort(l:pomList)
    call reverse(l:pomList) "Build the dependencies first.

    "Does all the work.
    let l:prjIdPomDict = MvnGetPrjIdPomDict(l:prjIdPomFilename)
    let l:prjData = MvnBuildProjectTree(l:pomList, l:prjIdPomDict)
    call MvnSetPrjIdPomDict(l:prjIdPomFilename, l:prjIdPomDict)

    "Insert the tree into current file (should be a project file).
    let l:insertPoint = line(".")
    call append(l:insertPoint, l:prjData)
endfunction; "}}}

function! MvnBuildProjectTree(pomList, prjIdPomDict) "{{{
"Build a Project directory tree maven style in the cursor position in the
"current file. On completion use Project \R to populate with files.
"a:pomList - build a project tree for each pom.xml in the list.
"a:prjIdPomDict - project configuration store, see MvnSetPrjIdPomDict().
"return - a list containing the new text representing the project to
"       display in the project tree.
"{{{ body
    let l:prjTreeTxt = []
    let l:prjIdPath = {}
    let l:fileFilter = join(g:mvn_javaSrcFilterList,' ').' '.join(g:mvn_resourceFilterList, ' ')
    let l:javaSrcExtList = MvnFilterToExtList(g:mvn_javaSrcFilterList)
    let l:javaResrcExtList = MvnFilterToExtList(g:mvn_resourceFilterList)
    "mvn project directory entry.
    let l:currentPom = 0
    let l:prjIndx = 0
    let l:indentCount = 0
    while l:currentPom < len(a:pomList)
        let l:currentPom = MvnCreateSingleProjectEntry(a:pomList, l:currentPom, l:prjTreeTxt,
            \ l:prjIndx, l:javaSrcExtList, l:javaResrcExtList, l:fileFilter, indentCount,
            \ a:prjIdPomDict)
        let l:currentPom += 1
    endwhile
    return l:prjTreeTxt
endfunction; "}}} body }}}

"{{{ project pom/dependency dict
function! MvnGetPrjPomDict(projectHomePath, prjIdPomDict) "{{{
"Retrieve the dict containing project layout data. Extract data from the
"pom.xml and create the project pom dict(prjPomDict) if the prjPomDict[created]
"date < pom.xml modified date else get the prjPomDict from the environment
"file 'in.vim'.  Update the project in.vim file if the prjPomDict is recreated.
"a:projectHomePath - the directory containing the pom.xml.
"a:prjIdPomDict - master project configuration store, see MvnSetPrjIdPomDict().
"return - prjPomDict containing the pom data.
    let l:doRecreate = 1
    let l:inVimFile = a:projectHomePath.'/in.vim'
    let l:prjPomDict = MvnLoadPrjPomDict(l:inVimFile)
    if has_key(l:prjPomDict, 'created')
        if l:prjPomDict['created'] < getftime(a:projectHomePath.'/pom.xml')
            let l:doRecreate = 0
        endif
    endif
    if l:doRecreate == 1
        let l:mvnData = MvnGetPomFileData(a:projectHomePath)
        let l:prjPomDict = MvnCreatePomDict(l:mvnData, a:projectHomePath, l:prjPomDict)
        "Store in in.vim and the master project dict.
        call MvnUpdateFile(l:inVimFile, 'g:mvn_currentPrjDict',
            \'let g:mvn_currentPrjDict='.string(l:prjPomDict))
        let a:prjIdPomDict[l:prjPomDict.id] = l:prjPomDict
    endif
    return l:prjPomDict
endfunction; "}}}

function! MvnGetPrjIdPomDict(filename) "{{{
"a:filename - the location of the prjIdPomDict file.
"return - prjIdPomDict, see MvnSetPrjIdPomDict().
    let l:prjIdPomDict = {}
    if filereadable(a:filename)
        let l:lineList = readfile(a:filename)
        if len(l:lineList) > 1
            throw "PrjIdPomDict file:".a:filename." has incorrect line count:".
            \len(l:lineList)."."
        elseif len(l:lineList) == 1
            if type(l:lineList[0]) == type({})
                let l:prjIdPomDict = eval(l:lineList[0]
            endif
        endif
    endif
    return l:prjIdPomDict
endfunction; "}}}

function! MvnSetPrjIdPomDict(filename, prjIdPomDict) "{{{
"Write out the master project dict to disk.
"a:prjIdPomDict - Dict store for all projects in the tree.
"   key: groupId:artifactId:version - project unique identifier.
"   value: a dict containing individual pom data ie prjPomDict.
    call writefile([string(a:prjIdPomDict)], a:filename)
endfunction; "}}}
"}}} project pom/dependency dict

"{{{ tree build functions
"{{{ MvnCreateSingleProjectEntry
function! MvnCreateSingleProjectEntry(pomList, currentPom, prjTreeTxt,
    \ prjIndx, srcExtList, resrcExtList, fileFilter, indentCount,
    \ prjIdPomDict)
"Build the tree structure into a:prjTreeTxt for the maven top level dirs:
"   src/main/java, src/main/resources, src/main/webapp, src/test/java
"   src/tset/resources. Recursively build subprojects.
"a:pomList - the list of poms for a project and its child projects.
"a:currentPom - an index into a:pomList.
"a:prjTreeTxt - a list containing the text for the view of the project.
"a:prjIndx - the insert point for new tree text into a:prjTreeTxt list.
"   Decremented on the recursive call.
"a:srcExtList, a:resrcExtList - the filename extensions to search on in
"   the creation of the directory tree.
"a:fileFilter - the extensions (ie txt,java...) as filters (ie *.txt,*.java)
"a:indentCount - the indentation (number of spaces) for the tree text.
"   Incrmented on each recursive call.
"a:prjIdPomDict - project configuration store, see MvnSetPrjIdPomDict().
    let l:pomFile = a:pomList[a:currentPom]
    let l:projectPath = substitute(l:pomFile, "/pom.xml", "", "g")
    let l:projectName = matchstr(l:projectPath, "[^/]\\+.$")
    let l:allExtList = extend(extend([], a:srcExtList), a:resrcExtList)
    let l:prjPomDict= MvnGetPrjPomDict(l:projectPath, a:prjIdPomDict)

    call insert(a:prjTreeTxt, repeat(' ', a:indentCount).l:projectName."="
        \  .l:projectPath." CD=. in=in.vim filter=\"".a:fileFilter."\" {", a:prjIndx)

    if a:prjIndx < 0
        call insert(a:prjTreeTxt, repeat(' ', a:indentCount)."}", a:prjIndx)
    else
        call add(a:prjTreeTxt, repeat(' ', a:indentCount)."}")
    endif

    "src main package dirs.
    call MvnBuildTopLevelDirEntries("srcMain", l:projectPath, l:prjPomDict.srcMain,
        \ a:prjTreeTxt, a:prjIndx - 1, a:srcExtList, a:indentCount)
    call MvnBuildTopLevelDirEntries("webapp", l:projectPath, s:mvn_projectMainWebapp,
        \ a:prjTreeTxt, a:prjIndx - 1, l:allExtList, a:indentCount)
    "src test package dirs.
    call MvnBuildTopLevelDirEntries("srcTest", l:projectPath, l:prjPomDict.srcTest,
        \ a:prjTreeTxt, a:prjIndx - 1, a:srcExtList, a:indentCount)
    "resource dirs.
    call MvnBuildTopLevelDirEntries("resrcMain", l:projectPath, l:prjPomDict.resrcMain[0],
        \ a:prjTreeTxt, a:prjIndx - 1, a:resrcExtList, a:indentCount)
    call MvnBuildTopLevelDirEntries("resrcTest", l:projectPath, l:prjPomDict.resrcTest[0],
        \ a:prjTreeTxt, a:prjIndx - 1, a:resrcExtList, a:indentCount)

    let l:currentPom = a:currentPom
    let l:isChild = 1
    while !(l:currentPom + 1 > len(a:pomList) - 1) && l:isChild
        let l:nextPomFile = a:pomList[l:currentPom + 1]
        let l:nextProjectPath = substitute(l:nextPomFile, "/pom.xml", "", "g")
        let l:isChild = match(l:nextProjectPath, l:projectPath) > -1
        if l:isChild
            let l:currentPom = MvnCreateSingleProjectEntry(a:pomList, l:currentPom + 1, a:prjTreeTxt,
                \ a:prjIndx - 1, a:srcExtList, a:resrcExtList, a:fileFilter, a:indentCount + 1,
                \ a:prjIdPomDict)
        endif
    endwhile
    return l:currentPom
endfunction; "}}} MvnCreateSingleProjectEntry

"{{{ MvnBuildTopeLevelDirEntries
function! MvnBuildTopLevelDirEntries(dirName, mvnProjectPath, relativePath,
    \masterProjectEntry, masterProjectIndx, javaSrcExtList, indentCount)
"Construct the directories for a maven project. Called once for each of:
"   src/main/java, src/main/resources, src/main/webapp, src/test/java,
"   src/test/resources
    if isdirectory(a:mvnProjectPath."/".a:relativePath)
        let l:dirEntry = MvnBuildDirEntry(a:dirName, a:relativePath, a:indentCount + 1)
        let l:mainPackageList = MvnBuildDirList(a:mvnProjectPath, "/".a:relativePath."/", a:javaSrcExtList)
        let l:mainPackageEntries = MvnBuildSiblingDirEntries(l:mainPackageList, a:indentCount + 2)
        call extend(l:dirEntry, l:mainPackageEntries, -1)
        call extend(a:masterProjectEntry, l:dirEntry, a:masterProjectIndx)
    endif
endfunction; "}}} MvnBuildTopeLevelDirEntries

function! MvnBuildSiblingDirEntries(dirList, indentCount) "{{{ 2
"Create a list with elements representing the directory list.
"Return - the list representing the dirList of sibling directories.
    let l:dirEntries = []
    for dirName in a:dirList
        let l:dirEntry = MvnBuildDirEntry(substitute(dirName, "/", ".", "g"), dirName, a:indentCount)
        call extend(l:dirEntries, l:dirEntry)
    endfor
    return l:dirEntries
endfunction; "}}} 2

function! MvnBuildDirEntry(dirName, dirPath, indentCount) "{{{ 2
"Create an entry for a new directory.
"Return - a 2 element list representing the directory.
    let l:dirEntry = []
    call add(l:dirEntry, repeat(' ', a:indentCount).a:dirName."=".a:dirPath." {")
    call add(l:dirEntry, repeat(' ', a:indentCount)."}")
    return l:dirEntry
endfunction; "}}} 2

function! MvnBuildDirList(mvnProjectPath, projectComponentDir, extensionList) "{{{ 2
"Find directories containing relevant files.
"mvnProjectPath - the dir containing the pom.
"projectComponentDir - ie /src/main/java/, /src/test/java/
"extensionList - a list of acceptable filetypes ie java, html, js, xml, js
"Return - a list of directories containing the relevant files.
    let l:cmd = "find ".a:mvnProjectPath.a:projectComponentDir."  -print"
    let l:filesList = split(system(l:cmd))
    let l:directoryList= []
    for absoluteFilename in l:filesList
        if !isdirectory(absoluteFilename) "directories must contain files
            let l:extension = matchstr(absoluteFilename, "\\.[^.]\\+$")
            let l:extension = substitute(l:extension, ".", "", "")
            if MvnIsInList(a:extensionList, l:extension) "only add directories for file types we care about
                let l:relativeName = matchstr(absoluteFilename, "[^/]\\+.$")
                let l:packageDir = substitute(absoluteFilename, "\/[^/]\\+.$", "", "")
                if match(l:packageDir."/",  a:projectComponentDir."$") == -1
                    let l:pos = matchend(l:packageDir, a:projectComponentDir )
                    let l:packageName = strpart(l:packageDir, l:pos)
                    if !MvnIsInList(l:directoryList, l:packageName)
                        call add(l:directoryList, l:packageName)
                    endif
                endif
            endif
        endif
    endfor
    return l:directoryList
endfunction; "}}} 2

function! MvnIsInList(list, value) "{{{ 2
"Could have used index(list, value) >= 0
    for item in a:list
        if item == a:value
            return 1
        endif
    endfor
    return 0
endfunction; "}}} 2

function! MvnTrimStringPre(str, exp) "{{{
"Trim the string up to the first exp
"Return - the str minus leading chars up to the start of exp.
    let l:result = ""
    let l:pos = match(a:str, a:exp)
    if l:pos > -1
        let l:result = strpart(a:str, l:pos)
    endif
    return l:result
endfunction "}}}

function! MvnTrimStringPost(str, exp) "{{{
"Trim the string after the last exp match.
"Return - the str minus chars after the end of exp.
    let l:result = ""
    let l:pos = matchend(a:str, a:exp)
    if l:pos > -1
        let l:result = strpart(a:str, 0, l:pos)
    endif
    return l:result
endfunction "}}}

function! MvnFilterToExtList(fileFilterList) "{{{ 2
"Strip the *. from the extension ie '*.java' becomes 'java'.
"fileFilterList - the list of file filters.
"Return - the list of extensions.
    let l:fileExtList = []
    for filter in a:fileFilterList
        let l:extension = matchstr(filter, "\\w\\+")
        call add(l:fileExtList, l:extension)
    endfor
    return l:fileExtList
endfunction; "}}} 2
"}}} tree build functions

"{{{ project utils
function! MvnGetPrjIdPomFilename() "{{{
"Check the current window is the project window.
"{{{ body
    if !exists('g:proj_running')
        throw "Is project running? Activate with ':Project'."
    endif
    if bufnr('%') != g:proj_running
        throw "Please select the project window."
    endif
    let l:prjIdPomFilename= bufname('%')."-mvn-ide"
    return  l:prjIdPomFilename
endfunction; "}}} body }}}
"}}} project utils

"{{{ xml pom functions
function! MvnGetPomFileData(projectHomePath) "{{{
"run maven to collect classpath and effective pom data as a string.
"{{{ body
    let l:mvnData = system("cd ".a:projectHomePath."; "
        \."mvn org.apache.maven.plugins:maven-dependency-plugin:2.4:build-classpath"
        \." org.apache.maven.plugins:maven-help-plugin:2.1.1:effective-pom")
    return l:mvnData
endfunction; "}}} body }}}

function! MvnCreatePomDict(mvnData, projectHome, prjPomDict) "{{{ 2
"Hacked from MvnGetPomDependencies.
"Extract all required config from the pom data and cache in the dict.
"a:mvnData the text from a maven invocation, see MvnGetPomFileData().
"a:projectHome the directory containing pom.xml.
"a:prjPomDict a dict containing defaults read from in.vim.
"   keys: id, created, home, classpath, dependencies, srcMain, srcTest,
"   classMain, classTest, resrcMain, resrcTest.
"Return prjPomDict.
"{{{ 3
    let pomDict = a:prjPomDict
    let pomDict['created'] = localtime()
    let pomDict['home'] = a:projectHome
    let pomDict['classpath'] = MvnBuildRunClassPath(a:mvnData)
    let l:effectivePom = a:mvnData
    let l:effectivePom = MvnTrimStringPre(l:effectivePom, "<project ")
    let l:effectivePom = MvnTrimStringPost(l:effectivePom, "</project>")
    let l:effectivePom = substitute(l:effectivePom, "\n", "", "g")
    let l:pomFilename = s:mvn_tmpdir."/effective-pom.xml"
    call writefile([l:effectivePom], l:pomFilename)
    "project pom id query
    let pomDict['id'] = MvnGetPomId(l:pomFilename)
    "dependency query
    let l:query = "/project/dependencies/*"
    let l:rawNodeList = MvnGetXPath(l:pomFilename, l:query)
    let l:nodeList = MvnParseNodesToList(l:rawNodeList)
    let l:dependencyIdList = MvnGetDependencyIdList(l:nodeList)
    let pomDict['dependencies'] = l:dependencyIdList
    "TODO look at doing something with additional paths. We are only
    "taking the first path and ignoring the rest.
    "source main query
    let pomDict['srcMain'] =  MvnGetStringsFromXPath(l:pomFilename,
        \"/project/build/sourceDirectory/text\(\)")[0]
    "source test query
    let pomDict['srcTest'] =  MvnGetStringsFromXPath(l:pomFilename,
        \"/project/build/testSourceDirectory/text\(\)")[0]
    "main class query
    let pomDict['classMain'] =  MvnGetStringsFromXPath(l:pomFilename,
        \"/project/build/outputDirectory/text\(\)")[0]
    "class test query
    let pomDict['classTest'] =  MvnGetStringsFromXPath(l:pomFilename,
        \"/project/build/testOutputDirectory/text\(\)")[0]
    "resource main query
    let pomDict['resrcMain'] =  MvnGetStringsFromXPath(l:pomFilename,
        \"/project/build/resources/resource/directory/text\(\)")
    "resource test query
    let pomDict['resrcTest'] =  MvnGetStringsFromXPath(l:pomFilename,
        \"/project/build/testResources/testResource/directory/text\(\)")
    call delete(s:mvn_tmpdir."/effective-pom.xml")
    call MvnDefaultDictConfigurables(pomDict)
    return pomDict
endfunction; "}}} 3 }}} 2

function! MvnDefaultDictConfigurables(pomDict) "{{{ 2
    if !has_key(a:pomDict, 'webapp')
        let a:pomDict.webapp = s:mvn_projectMainWebapp
    endif
endfunction; "}}} 2

function! MvnGetPomDependencies(mvnData) "{{{ 2
"REPLACED with MvnCreatePomDict
"Build a list of dependencies for a maven project.
"Return a list of dependency id's for a project in the form of:
"  groupId:artifactId:version
"{{{ 3
    let l:query = "/project/dependencies/*"
    let l:effectivePom = a:mvnData
    let l:effectivePom = MvnTrimStringPre(l:effectivePom, "<project ")
    let l:effectivePom = MvnTrimStringPost(l:effectivePom, "</project>")
    let l:effectivePom = substitute(l:effectivePom, "\n", "", "g")
    call writefile([l:effectivePom], s:mvn_tmpdir."/effective-pom.xml")
    let l:rawDependencyList = MvnGetXPath(s:mvn_tmpdir."/effective-pom.xml", l:query)
    call delete(s:mvn_tmpdir."/effective-pom.xml")
    let l:dependencyNodeList = MvnParseNodesToList(l:rawDependencyList)
    let l:dependencyIdList = MvnGetDependencyIdList(l:dependencyNodeList)
    return l:dependencyIdList
endfunction; "}}} 3 }}} 2

function! MvnGetPomId(pomFile) "{{{ 2
"Build an identifier for a maven project in the form groupId:artifactId:version
"pomFile - path/filname of the pom.xml.
"Return - the project identifier ie groupId:artifactId:version.
"{{{ 3
    let l:query = "/project/groupId/text\(\)"
    let l:groupId = get(MvnGetXPath(a:pomFile, l:query), 2)
    let l:query = "/project/artifactId/text\(\)"
    let l:artifactId = get(MvnGetXPath(a:pomFile, l:query), 2)
    let l:query = "/project/version/text\(\)"
    let l:version = get(MvnGetXPath(a:pomFile, l:query), 2)
    return l:groupId.":".l:artifactId.":".l:version
endfunction; "}}} 3 }}} 2

function! MvnGetDependencyIdList(dependencyNodeList) "{{{ 2
"Compose the id from each dependency node fragment.
"Return - a list of dependency id's of for groupId:artifactId:version
"{{{ 3
    let l:idDependencyList = []
    for nodeText in a:dependencyNodeList
        let l:query = "/dependency/groupId/text\(\)"
        let l:groupId = get(MvnGetXPathFromTxt(nodeText, l:query), 2)
        let l:query = "/dependency/artifactId/text\(\)"
        let l:artifactId = get(MvnGetXPathFromTxt(nodeText, l:query), 2)
        let l:query = "/dependency/version/text\(\)"
        let l:version = get(MvnGetXPathFromTxt(nodeText, l:query), 2)
        call add(idDependencyList, l:groupId.":".l:artifactId.":".l:version)
    endfor
return l:idDependencyList
endfunction; "}}} 3 }}} 2

function! MvnGetStringsFromXPath(xmlFile, query) "{{{ 2
"xmlFile - the path/filename of the xmlfile.
"query - the XPath query.
"Return a non empty string list query data.
"{{{ 3
    let l:rawNodeList = MvnGetXPath(a:xmlFile, a:query)
    let l:nodeList = MvnParseNodesToList(l:rawNodeList)
    if len(l:nodeList) < 1
        throw "No elements for ".a:query.". Check 'mvn clean install'."
    endif
    return l:nodeList
endfunction; "}}} 3 }}} 2

function! MvnParseNodesToList(xpathOutputList) "{{{ 2
"Take the string output from xpath and create a list item for each node.
"xpathOutputList - the xpath string result from a query as a list.
"Return - cleaned xpath output as a list - one node in each list item.
"{{{ 3
    let l:item = ""
    let l:haveNode = 0
    let l:lineList = []
    for line in a:xpathOutputList
        let l:pos = match(line, "\\c-- node --")
        if l:pos > -1
            if l:pos > 0
                "-- node -- separator is not always on a new line!
                let l:item .= strpart(line, 0, l:pos)
            endif
            if strlen(l:item) > 0
                call add(l:lineList, l:item)
                let l:item = ""
            endif
            let l:haveNode = 1
        elseif l:haveNode == 1
            let l:item .= matchstr(line, "\\p\\+")
        endif
    endfor
    if strlen(l:item) > 0
        call add(l:lineList, l:item)
    endif
    return l:lineList
endfunction; "}}} 3 }}} 2

function! MvnGetXPathFromTxt(xmlText, query) "{{{ 2
"xmlText- the xml string to parse.
"query - the XPath query.
"Return a list query data.
"{{{ 3
    let l:cmd = substitute(s:mvn_xpathcmd, "filename", "", 'g')
    let l:cmd = substitute(l:cmd, "query", a:query, 'g')
    let l:resultList= split(system("echo \"".a:xmlText."\" |".l:cmd), "\n")
    return l:resultList
endfunction; "}}} 3 }}} 2

function! MvnGetXPath(xmlFile, query) "{{{ 2
"xmlFile - the path/filename of the xmlfile.
"query - the XPath query.
"Return a list query data.
"{{{ 3
    let l:cmd = substitute(s:mvn_xpathcmd, "filename", a:xmlFile, 'g')
    let l:cmd = substitute(l:cmd, "query", a:query, 'g')
    let l:resultList= split(system(l:cmd), "\n")
    return l:resultList
endfunction; "}}} 3 }}} 2
"}}} xml pom functions
"}}} Project ------------------------------------------------------------------

"{{{ Environment config -------------------------------------------------------
function! MvnRefreshPrjIdPomDict() "{{{
"Refresh the prjPomDict for each selected project(s).
"{{{ body
    let l:prjIdPomFilename = MvnGetPrjIdPomFilename()
    let l:prjIdPomDict = MvnGetPrjIdPomDict(l:prjIdPomFilename)
    let l:dirList = MvnGetProjectDirList("", 0)
    for dir in l:dirList
        try
            echo "Refresh ".dir."/in.vim"
            "the get does a refresh.
            call MvnGetPrjPomDict(dir, l:prjIdPomDict)
        catch /.*/
            echo "MvnRefresPrjIdPomDict error processing".
                \dir." ".v:exception." ".v:throwpoint
        endtry
    endfor
    "TODO cycle through l:prjIdPomDict and remove non existant projects.
    call MvnSetPrjIdPomDict(l:prjIdPomFilename, l:prjIdPomDict)
endfunction; "}}} body }}}

function! MvnBuildEnvSelection() "{{{
"Build the environment for the consecutive project entries.
"{{{ body
    let l:prjIdPomFilename = MvnGetPrjIdPomFilename()
    let l:dirList = MvnGetProjectDirList("", 0)
    let l:prjIdPomDict = MvnGetPrjIdPomDict(l:prjIdPomFilename)
    "echo("Calculate the jdk runtime library using java -verbose -h.")
    let l:jreLib = MvnGetJreRuntimeLib()
    for dir in l:dirList
        try
            call MvnBuildEnv(dir, l:prjIdPomDict, l:jreLib)
        catch /.*/
            echo "MvnBuildEnvSelection error processing".
                \dir." ".v:exception." ".v:throwpoint
        endtry
    endfor
    call MvnSetPrjIdPomDict(l:prjIdPomFilename, l:prjIdPomDict)
endfunction; "}}} body }}}

function! MvnBuildEnv(projectHomePath, prjIdPomDict, jreLib) "{{{
"Build the project in.vim sourced on access to a file in the project.
"Environment generated: g:vjde_lib_path, g:mvn_javadocPath,
"    g:mvn_javaSourcePath, g:mvn_currentPrjDict, path, tags.
"The environment paths include local project dependencies from the
"a:prjIdPomDict (see MvnSetPrjIdPomDict()).
"{{{ body
    let l:startTime = localtime()
    let l:projectHomePath = a:projectHomePath
    if strlen(l:projectHomePath) == 0
        let l:projectHomePath = MvnGetProjectHomeDir()
        if !filereadable(l:projectHomePath."/pom.xml")
            echo("No project file :".l:projectHomePath."/pom.xml")
            return
        endif
    endif

    let l:prjPomDict = MvnGetPrjPomDict(projectHomePath, a:prjIdPomDict)
    "let l:newline = "let g:mvn_currentPrjDict=" . string(l:prjPomDict)
    "call MvnUpdateFile(projectHomePath."/in.vim", "mvn_currentPrjDict", l:newline)

    "echo("\nBuild env for ".l:projectHomePath.".")
    "Get the maven local sibling dependencies for a project to add to the path instead of jars.
    let l:siblingProjectIdList = MvnGetLocalDependenciesList(l:prjPomDict.dependencies, a:prjIdPomDict)
    let l:projectIdList = insert(l:siblingProjectIdList, l:prjPomDict['id'])

    "Create the runtime classpath for the maven project.
    "echo("Calculate the runtime classpath using mvn dependency:build-classpath.") 21sec
    let l:mvnClassPath = l:prjPomDict['classpath']
    if strlen(l:mvnClassPath) == 0
        throw "No classpath."
        return
    endif

    let l:projectRuntimeDirs = MvnGetPathsFromPrjDict(a:prjIdPomDict, l:projectIdList, 'classMain')
    "Add l:projectRuntimeDirs (target/classes) to the path ahead of l:mvnClassPath (the jars).
    let l:newline = "let g:vjde_lib_path=\"".l:projectRuntimeDirs.":".a:jreLib.":".l:mvnClassPath."\""
    call MvnUpdateFile(projectHomePath."/in.vim", "vjde_lib_path", l:newline)

    "Install java sources (if the jars exist) and create the path to the sources for the maven project.
    "echo("Unpack dependency source if downloaded and create source path.")
    let l:result = MvnInstallArtifactByClassifier(g:mvn_javaSourceParentDir, l:mvnClassPath, "sources")
    let l:javaSourcePath = l:result[0]
    let l:unavailableSource = l:result[1]
    let l:javaSourcePath .= ":".g:mvn_additionalJavaSourcePath
    let l:projectJavaSourcePath = MvnGetPathsFromPrjDict(a:prjIdPomDict, l:projectIdList, 'srcMain')
    let l:allJavaSourcePath = l:projectJavaSourcePath . ":" . l:javaSourcePath
    let l:allJavaSourcePath = substitute(l:allJavaSourcePath, '::\+', ':', 'g')
    let l:newline = "let g:mvn_javaSourcePath=\"".l:allJavaSourcePath."\""
    call MvnUpdateFile(projectHomePath."/in.vim", "mvn_javaSourcePath", l:newline)

    "Install javadoc (if the jars exist) and create the path to the javadoc for the maven project.
    "echo("Unpack javadoc if downloaded and create javadoc path.")
    let l:result = MvnInstallArtifactByClassifier(g:mvn_javadocParentDir, l:mvnClassPath, "javadoc")
    let l:javadocPath = l:result[0]
    let l:unavailableJavadoc = l:result[1]
    let l:jdFromSource = MvnInstallJavadocFromSource(g:mvn_javadocParentDir, g:mvn_javaSourceParentDir,
            \l:unavailableJavadoc, l:unavailableSource)
    if strlen(l:jdFromSource) > 0
        let l:jdFromSource = ':'.l:jdFromSource
    endif
    let l:newline = "let g:mvn_javadocPath=\"".l:javadocPath.":".
        \g:mvn_additionalJavadocPath.l:jdFromSource."\""
    call MvnUpdateFile(projectHomePath."/in.vim", "mvn_javadocPath", l:newline)

    "set path. Include test source to allow for quick fix of junit failures
    "ie during mvn clean install.
    let l:srcPath = l:allJavaSourcePath . ':'.l:prjPomDict['srcTest']
    let l:path = MvnConvertToPath(l:srcPath)
    let l:newline = "let &path=\"".l:path."\""
    call MvnUpdateFile(projectHomePath."/in.vim", "let &path=", l:newline)

    "echo("Build tag files for all available source files.")
    let l:tagPath =  MvnBuildTags(l:prjPomDict['id'], l:javaSourcePath, l:projectIdList, a:prjIdPomDict)
    let l:newline = "let &tags=\"".l:tagPath."\""
    call MvnUpdateFile(projectHomePath."/in.vim", "tags", l:newline)
    echo "MvnBuildEnv Complete - ". projectHomePath. " ".eval(localtime() - l:startTime)."s"
endfunction; "}}} body }}}

function! MvnClasspathPreen(projectIdList, mvnClasspath) "{{{
"Return - the vim path from javaSourcePath.
    let l:jarList = split(a:mvnClasspath, ':')
    let l:idList = []
    let l:preenedList = []
    for name in l:jarList
        if len(name) > 0
            let l:id = MvnIdFromJarName(name)
            if len(l:id) > 0
                call add(l:idList, l:id)
            else
                call add(l:idList, '')
            endif
        endif
    endfor
    let l:idx = 0
    for jarId in l:idList
        let l:found = 0
        if len(jarId) > 0
            for prjId in a:projectIdList
                if prjId == jarId
                    let l:found = 1
                endif
            endfor
        endif
        if l:found == 0
            call add(l:preenedList, l:jarList[l:idx])
        endif
        let l:idx += 1
    endfor
    return join(l:preenedList, ':')
endfunction; "}}}

function! MvnIdFromJarName(mvnClassFilename) "{{{
"Return an id for the jar file from the maven repo path.
    let l:id = ''
    let l:pathElementList = split(a:mvnClassFilename, '/')
    let l:size = len(l:pathElementList)
    if l:size > 5
        let l:versionId = l:pathElementList[l:size - 2]
        let l:artifactId = l:pathElementList[l:size - 3]
        let l:groupId = l:pathElementList[l:size - 4]
        let l:id = l:groupId .':'. l:artifactId .':'. l:versionId
    endif
    return l:id
endfunction; "}}}

function! MvnConvertToPath(javaSourcePath) "{{{
"Return - the vim path from javaSourcePath.
    let l:pathList = split(a:javaSourcePath, ':')
    let l:path = ''
    for branch in l:pathList
        let l:path .= branch.'/'.'**,'
    endfor
    if strpart(l:path, len(l:path)-1, 1) == ','
        let l:path = strpart(l:path, 0, len(l:path)-1)
    endif
    return l:path
endfunction; "}}}

function! MvnGetLocalDependenciesList(dependencyIdList, prjIdPomDict) "{{{
"Return a list of maven ids of the local sibling projects depended on by
"this project. Remove dependency projects from prjIdPomDict if they no
"longer exist.
"a:dependencyIdList - list of ids of the form groupId:artifactId:version.
"a:prjIdPomDict - the dict of all sibling projects.
    let l:localDependencyIdList = []
    for dependencyId in a:dependencyIdList
        if has_key(a:prjIdPomDict, dependencyId)
            let l:prjPomDict = a:prjIdPomDict[dependencyId]
            if isdirectory(l:prjPomDict['home'])
                call add(l:localDependencyIdList, dependencyId)
            else
                call remove(l:prjIdPomDict, dependencyId)
            endif
        endif
    endfor
    return l:localDependencyIdList
endfunction; "}}}

function! MvnGetPathsFromPrjDict(prjIdPomDict, idList, attribute) "{{{
"Return a path by appending path a:attribute from a:prjIdPomDict for each
"project in a:idList.
"a:prjIdPomDict - project configuration store, see MvnSetPrjIdPomDict().
"a:idList - the list of project identifiers of form groupId:artifactId:varsion.
"a:attribute - ie 'srcMain'
    let l:dirs = []
    try
        for id in a:idList
            if has_key(a:prjIdPomDict[id], a:attribute)
                let l:dir = a:prjIdPomDict[id][a:attribute]
                if len(l:dir) > 0
                    call add(l:dirs, l:dir)
                endif
            endif
        endfor
    catch /.*/
        throw "id=".string(id)." idList=".string(a:idList)." ".v:exception." ".v:throwpoint
    endtry
    let l:dirPath = join(l:dirs, ":")
    return l:dirPath
endfunction; "}}}

function! MvnGetProjectHomeDir() "{{{
"return - the absolute path for the project ie where the pom.xml is.
    let l:projTargetClassesPath = matchstr(system('pwd'), "\\p\\+")
    return l:projTargetClassesPath
endfunction; "}}}

function! MvnGetJreRuntimeLib() "{{{
    let l:jreLib = matchstr(system("java -verbose -h |grep Opened"), "Opened \\p\\+")
    let l:jreLib = matchstr(l:jreLib, "/.\\+jar")
    return l:jreLib
endfunction; "}}}

function! MvnBuildRunClassPath(mvnData) "{{{
"Create the classpath from the maven project.
"return - the maven classpath
    "let l:runMaven ='mvn dependency:build-classpath'
    "let l:mavenClasspathOutput = system(l:runMaven)
    let l:mavenClasspathOutput = a:mvnData
    let l:pos = matchend(l:mavenClasspathOutput, 'Dependencies classpath:')
    let l:clpath = ""
    if l:pos != -1
        let l:endPos = match(l:mavenClasspathOutput, '\[INFO\]', l:pos)
        "let l:clpath = matchstr(l:mavenClasspathOutput, "\\p\\+", l:pos)
        let l:clpath = strpart(l:mavenClasspathOutput, l:pos, l:endPos-l:pos)
        let l:clpath = substitute(l:clpath, '\n', '', 'g')
    else
        throw "MvnBuildRunClassPath():Failed on mvn dependency:build-classpath.".l:pos
    endif
    return l:clpath
endfunction; "}}}

function! MvnExecuteFile(filename) "{{{
"execute script locally ie so script (s:) variables are set.
    if filereadable(a:filename)
        let l:lines = readfile(a:filename)
        for line in l:lines
            exec line
        endfor
    endif
endfunction; "}}}

function! MvnUpdateFile(filename, id, newline) "{{{
"Update the in.vim Project file. Lookup the line by a:id ie the environment
"  variable name and replace with a:newline. If an entry for the variable
"  does not exist in the file then add it.
    if filereadable(a:filename)
        let l:lines = readfile(a:filename)
    else
        let l:lines = []
    endif
    let l:lineNo = match(l:lines, a:id)
    if l:lineNo >= 0
        "The entry exists so remove it and add it back in the same position.
        call remove(l:lines, l:lineNo)
        call insert(l:lines, a:newline, l:lineNo)
    else
        "Does not exist so add it to the end of the file.
        call add(l:lines, a:newline)
    endif
    call writefile(l:lines, a:filename)
endfunction; "}}}

function! MvnLoadPrjPomDict(filename) "{{{
"Return the project pom dict if it exists else empty dict.
"a:filename the absolute filename of in.vim for the project.
    let l:prjPomDict= {}
    if filereadable(a:filename)
        let l:lines = readfile(a:filename)
        let l:lineNo = match(l:lines, 'g:mvn_currentPrjDict')
        if l:lineNo >= 0
           let l:line = get(l:lines, l:lineNo)
           let l:pos = matchend(l:line, 'g:mvn_currentPrjDict.*=')
           let l:prjPomDict= eval(strpart(l:line, l:pos))
        endif
    endif
    return l:prjPomDict
endfunction; "}}}
"}}} Environment config -------------------------------------------------------

"{{{ Compiler -----------------------------------------------------------------
"{{{ mavenOutputProcessorPlugins
"plugins to parse maven output to a quickfix list ie junit,checkstyle...
let s:MvnPlugin = {} "{{{ mavenProcessorParentPlugin
function! s:MvnPlugin.New()
    let l:newMvnPlugin = copy(self)
    let l:newMvnPlugin._mvnOutputList = []
    let l:newMvnPlugin._startRegExpList = []
    let l:newMvnPlugin._currentLine = 0
    return l:newMvnPlugin
endfunction
function! s:MvnPlugin.addStartRegExp(regExp) dict
    call add(self._startRegExpList, a:regExp)
endfunction
function! s:MvnPlugin.processErrors() dict
    let l:ret = {'lineNumber': a:lineNo, 'quickfixList': []}
    return l:ret
endfunction
function! s:MvnPlugin.setOutputList(mvnOutputList) dict
    let self._mvnOutputList = a:mvnOutputList
endfunction
function! s:MvnPlugin.processAtLine(lineNo) dict "{{{ processAtLine
"Check the lineNo for the plugin message
"a:mvnOutputList - the complete mvn output log as a list.
"a:lineNo - the line number of the mvnOutputList to begin processing.
"return dict { lineNumber, quickfixList }
"   lineNumber  - set as the input lineNo when no processing occurred,
"   otherwise the final line of processing.
"   quickfixList - a quickfix list resulting from the processing of the
"   log lines. quickfix dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': a:lineNo, 'quickfixList': []}
    let self._currentLine = a:lineNo
    let l:fail = 1
    for regExp in self._startRegExpList
        if match(self._mvnOutputList[self._currentLine], regExp) != 0
            return l:ret
        endif
        let self._currentLine += 1
    endfor
    let l:ret = self.processErrors()
    return  l:ret
endfunction "}}} processAtLine }}} mavenProcessorParent

let s:Mvn2Plugin = {} "{{{ maven2Plugin
function! s:Mvn2Plugin.New()
   let this = copy(self)
   let super = s:MvnPlugin.New()
   call extend(this, deepcopy(super), "keep")
   call this.addStartRegExp('^\[ERROR\] BUILD FAILURE')
   call this.addStartRegExp('^\[INFO\] -\+')
   call this.addStartRegExp('^\[INFO\] Compilation failure')
   return this
endfunction
function! s:Mvn2Plugin.processErrors()
    let l:ret = {'lineNumber': a:lineNo, 'quickfixList': []}
    return l:ret
endfunction
function! s:Mvn2Plugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}

    let l:errorFinish = match(self._mvnOutputList, '^\[INFO\] -\+',
        \ self._currentLine + 1)
    let l:quickfixList = []
    let l:lineNo = self._currentLine + 1
    if l:errorFinish > -1
        while l:lineNo < l:errorFinish
            let l:line = self._mvnOutputList[l:lineNo]
            try
                if len(l:line) == 0
                    let l:lineNo += 1
                    continue
                endif
                let l:posStart = 0
                let l:posEnd = match(l:line, ':')
                let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:posEnd = match(l:line, ',', l:posStart)
                let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ']', l:posStart)
                let l:errorColNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:message = strpart(l:line, l:posStart)
                let l:fixList = {'bufnr': '', 'filename': l:filename,
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixList)
                let l:lineNo += 1
            catch /notErrorLine/
                let l:exception=1
            endtry
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:lineNo
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction "}}} processErrors }}} maven2Plugin

let s:Mvn3Plugin = {} "{{{ maven3Plugin
function! s:Mvn3Plugin.New()
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^\[ERROR\] COMPILATION ERROR :')
    return this
endfunction
function! s:Mvn3Plugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}

    let l:errorFinish = match(self._mvnOutputList, '^\[INFO\] \d\+ error',
        \ self._currentLine + 1)
    let l:quickfixList = []
    if l:errorFinish > -1
        let l:lineNo = self._currentLine + 1
        while l:lineNo < l:errorFinish
            let l:line = self._mvnOutputList[l:lineNo]
            try
                if 0 != match(l:line, '\[ERROR\]')
                    throw 'notErrorLine'
                endif
                let l:posStart = 8
                let l:posEnd = match(l:line, ':')
                let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:posEnd = match(l:line, ',', l:posStart)
                let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ']', l:posStart)
                let l:errorColNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 2
                let l:message = strpart(l:line, l:posStart)

                let l:fixList = {'bufnr': '', 'filename': l:filename,
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixList)

            catch /notErrorLine/
                let l:exception=1
            endtry
            let l:lineNo += 1
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:lineNo
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction "}}} processErrors }}} maven3Plugin

let s:JunitPlugin = {} "{{{ junitPlugin
function! s:JunitPlugin.New()
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    return this
endfunction "}}} junitPlugin

let s:Junit3Plugin = {} "{{{ junit3Plugin
function! s:Junit3Plugin.New()
    let this= copy(self)
    let super = s:JunitPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^ T E S T S')
    call this.addStartRegExp('^-\+')
    return this
endfunction
function! s:Junit3Plugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}
    let l:testFinish = match(self._mvnOutputList, '^Results :',
        \ self._currentLine + 1)
    if l:testFinish != -1
        let l:testFinish = match(self._mvnOutputList, '^Tests run:',
            \ l:testFinish)
    endif

    let l:quickfixList = []
    if l:testFinish > -1
        let l:lineNo = self._currentLine + 1
        while l:lineNo < l:testFinish
            let l:line = self._mvnOutputList[l:lineNo]
            if (-1 != match(l:line, '<<< FAILURE!$') ||
                \ -1 != match(l:line, '<<< ERROR!$')) &&
                \ -1 == match(l:line, '^Tests run:')
                let l:resultDict = self.doFailure(l:lineNo, l:testFinish)
                let l:fixList = l:resultDict.fixList
                let l:lineNo = l:resultDict.lineNo
                call add(l:quickfixList, l:fixList)
            endif
            let l:lineNo += 1
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:testFinish
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction
function! s:Junit3Plugin.doFailure(lineNo, finishLineNo)
    let l:lineNo = a:lineNo + 1
    let l:message = self._mvnOutputList[l:lineNo]
    let l:failFinishLine = match(self._mvnOutputList, '^$', l:lineNo)
    if l:failFinishLine > a:finishLineNo
        throw "Unable to parse Junit error."
    endif
    let l:line = self._mvnOutputList[l:failFinishLine - 1]
    let l:posStart = match(l:line, '(') + 1
    let l:posEnd = match(l:line, ':')
    let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
    let l:posStart = l:posEnd + 1
    let l:posEnd = match(l:line, ')', l:posStart)
    let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)
    let l:fileNoExt = strpart(l:filename, 0, strridx(l:filename, '.'))
    let l:posStart = matchend(l:line, '^\s\+at\s\+')
    let l:posEnd = match(l:line, '.'.l:fileNoExt)
    let l:package = strpart(l:line, l:posStart, l:posEnd-l:posStart)
    let l:classname = l:package.'.'.l:fileNoExt
    let l:filename = substitute(l:classname, '\.', '/', 'g')
    let l:filename .= '.java'
    let l:absoluteFilename = findfile(l:filename)

    let l:fixList = {'bufnr': '', 'filename': l:absoluteFilename,
        \'lnum': l:errorLineNo, 'pattern': '', 'col': '',
       \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

    return {'lineNo': l:failFinishLine, 'fixList': l:fixList }
endfunction "}}} processErrors }}} junit3Plugin

let s:CheckStylePlugin = {} "{{{ checkStylePlugin
function! s:CheckStylePlugin.New()
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^\[INFO\] Starting audit...')
    return this
endfunction
function! s:CheckStylePlugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}

    let l:errorFinish = match(self._mvnOutputList, '^Audit done.',
        \ self._currentLine)
    let l:quickfixList = []
    if l:errorFinish > -1
        let l:lineNo = self._currentLine
        while l:lineNo < l:errorFinish
            let l:line = self._mvnOutputList[l:lineNo]
            try
                let l:posStart = 0
                let l:posEnd = match(l:line, ':')
                let l:filename = strpart(l:line, l:posStart, l:posEnd-l:posStart)
                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ':', l:posStart)
                let l:errorLineNo = strpart(l:line, l:posStart, l:posEnd-l:posStart)

                let l:posStart = l:posEnd + 1
                let l:posEnd = match(l:line, ':', l:posStart)
                let l:errorColNo = ''
                if l:posEnd > -1
                    let l:errorColNo = strpart(l:line, l:posStart,
                            \l:posEnd-l:posStart)
                    let l:posStart = l:posEnd + 1
                endif

                let l:message = strpart(l:line, l:posStart + 1)

                let l:fixList = {'bufnr': '', 'filename': l:filename,
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixList)

            catch /notErrorLine/
                let l:exception=1
            endtry
            let l:lineNo += 1
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:lineNo
            let l:ret.quickfixList = l:quickfixList
        endif
    endif
    return l:ret
endfunction "}}} processErrors }}} checkStylePlugin

"{{{ pluginListInit
function! MvnPluginInit()
    let s:plugins = []
    for plugin in g:mvn_pluginList
        call add(s:plugins, eval("s:".plugin).New())
    endfor
    return s:plugins
endfunction;
function! MvnPluginOutputInit(pluginList, mvnOutputList)
    for plugin in a:pluginList
        call plugin.setOutputList(a:mvnOutputList)
    endfor
endfunction;
"}}} pluginListInit
"}}} mavenOutputProcessorPlugins

function! MvnCompile() "{{{
"Full project compilation with maven.
"   Don't use standard quickfix functionality - maven output seems
"   challenging for vim builtin error formatting, so implement explicit
"   invocation of compile, processing of output messages and
"   build of quickfix list.
    call setqflist([])
    let l:outfile = s:mvn_tmpdir."/mvn.out"
    call delete(l:outfile)
    "surefire.useFile=false - force junit output to the console.
    let l:cmd = "mvn clean install -Dsurefire.useFile=false"
    let l:cmd = "mvn clean ".
    \"org.apache.maven.plugins:maven-compiler-plugin:".
    \g:mvn_compilerVersion.":compile install -Dsurefire.useFile=false"

    if strlen(v:servername) == 0
        let l:cmd = "!".l:cmd
        let l:cmd .=" | tee ".l:outfile
        exec l:cmd
        call MvnOP2QuickfixList(l:outfile)
    else
        let l:Fn = function("MvnOP2QuickfixList")
        call asynccommand#run(l:cmd, l:Fn)
    endif
endfunction; "}}}

function! MvnOP2QuickfixList(outputFile) "{{{
    let l:mvnOutput = readfile(a:outputFile)
    let l:outSize = len(l:mvnOutput)
    if l:outSize == 0
        throw "No Maven compile output."
    endif
    let l:quickfixList = MvnCompileProcessOutput(l:mvnOutput)
    if len(l:quickfixList) > 0
        "fix from the last error in a file to the first error so the line numbers
        "are not contaminated.
        call reverse(l:quickfixList)
        call setqflist(l:quickfixList)
        "call feedkeys(":cc \<CR>")
        call feedkeys(":cope \<CR>")
    endif
endfunction; "}}}

function! MvnCompileProcessOutput(mvnOutput) "{{{
"Process the output of the maven command, contained in the mvnOutput list.
"   Iterate each line of the output list and process with plugin list.
"   If a plugin is able to process a line it takes over processing of the
"   mvnOutput list and iterates the list itself until processing of the
"   plugin specific message is completed. When the plugin can process the
"   mvnOutput list no further it returns control with the last line number
"   ie  where it's processing completed to allow processing to continue
"   by another plugin.
"a:mvnOutput - the output of the mvn command contained in a list.
"return - a quickfixList.
    let l:outSize = len(a:mvnOutput)
    call MvnPluginOutputInit(s:plugins, a:mvnOutput)
    let l:quickfixList = []
    let l:lineNo = 0
    while l:lineNo < l:outSize
        for plugin in s:plugins
            let processResult = plugin.processAtLine(l:lineNo)
            if processResult.lineNumber != l:lineNo
                let l:lineNo = processResult.lineNumber
                if len(processResult.quickfixList) > 0
                    call extend(l:quickfixList, processResult.quickfixList)
                endif
                continue
            endif
        endfor
        let l:lineNo += 1
    endwhile
    return l:quickfixList
endfunction; "}}}

function! MvnJavacCompile() "{{{
"Allow for quick single file compilation with javac.
    compiler javac_ex
    let l:envList = MvnTweakEnvForSrc(expand('%:p'))
    if empty(l:envList)
        return -1
    endif
    let l:target = l:envList[1]
    let l:classpath = l:envList[0]

    let &makeprg="javac  -g -d " . l:target . " -cp " . l:classpath . "  %"
    if strlen(v:servername) == 0
        make
    else
        "background execution of compile.
        call asynccommand#run(&makeprg, asynchandler#quickfix(&errorformat, ""))
    endif
endfunction; "}}}

function! MvnTweakEnvForSrc(srcFile) "{{{
"Set the environment variables relative to source file ie main/test.
"a:srcFile - the src file to set the env for.
"return list [runClassPath, targetDir, sourcePath, isTest, path]
"   runClassPath - the runtime runClassPath
"   targetDir- the path to build target dir.
"   sourcePath - the path of the source files.
"   isTest - 1/0 the file is/isn't test source.
" TODO: refactor to a map asap.
    let l:targetDir= ""
    let l:runClassPath = g:vjde_lib_path
    let l:envList = []
    let l:sourcePath = g:mvn_javaSourcePath
    let l:isTest = 0
    if match(a:srcFile, s:mvn_projectMainSrc) > 0
        let l:targetDir= g:mvn_currentPrjDict['home']."/".s:mvn_projectMainClasses
        let l:resourceDir = g:mvn_currentPrjDict['home']."/".s:mvn_projectMainResources
        if isdirectory(l:resourceDir)
            "TODO is this really needed? resources should already be included via
            "target/classes in g:vjde_lib_path
            let l:runClassPath .= l:resourceDir.":".l:runClassPath
        endif
    elseif match(a:srcFile, s:mvn_projectTestSrc) > 0
        let l:targetDir= g:mvn_currentPrjDict['home']."/".s:mvn_projectTestClasses
        let l:runClassPath = g:mvn_currentPrjDict['home']."/".s:mvn_projectTestClasses.":".l:runClassPath
        "TODO same as above. resource should already be included in the classpath
        let l:resourceDir = g:mvn_currentPrjDict['home']."/".s:mvn_projectTestResources
        let l:sourcePath = g:mvn_currentPrjDict['home']."/".s:mvn_projectTestSrc.":".l:sourcePath
        if isdirectory(l:resourceDir)
            let l:runClassPath .= l:resourceDir.":".l:runClassPath
        endif
        let l:isTest = 1
    else
        throw "Could not identify maven target directory / run classpath."
    endif

    call add(l:envList, l:runClassPath)
    call add(l:envList, l:targetDir)
    call add(l:envList, l:sourcePath)
    call add(l:envList, l:isTest)
    return l:envList
endfunction; "}}}
"}}} Compiler -----------------------------------------------------------------

"{{{ Debugging ----------------------------------------------------------------
function! MvnDoDebug() "{{{
"<F3> Run
"<C-F5> Run Application
"<F5> Continue Execution
"<F7> Step Into a Function
"<F8> Next Instruction
"<F9> Set Breakpoint
"<F10> Print variable value under cursor

"   let g:jdbcmd = "jdb -classpath ./target/classes -sourcepath ./src/main/java com.encompass.App"
"   let l:debugger = "yavdb -s " . v:servername . " -t jdb \"" .  g:jdbcmd . "\""
"   let l:debugger = '!xterm \"yavdb -s DEBUG -t jdb\"'

" jdb -sourcepath -attach 11550
    if strlen(v:servername) == 0
        echo "No servername!"
    else

        "Prompt for the debug port number.
        let l:debugSelectionList=[]
        let l:firstOption = "0: Run and debug current file port:"
        let l:firstOption .= g:mvn_debugPortList[0]
        call add(l:debugSelectionList, l:firstOption)

        let l:count = 1
        for port in g:mvn_debugPortList
            call add(l:debugSelectionList, l:count . ") connect to " . port .".")
            let l:count += 1
        endfor

        call inputsave()
        let l:SelectedOption= inputlist(l:debugSelectionList)
        call inputrestore()

        if l:SelectedOption == -1 || l:SelectedOption > len(l:debugSelectionList)
            return
        endif

        "setup the env for test/main debug.
        let l:envList = MvnTweakEnvForSrc(expand('%:p'))
        if empty(l:envList)
            return -1
        endif
        let l:sourcepath = l:envList[2]

        if l:SelectedOption == 0
            let l:port= g:mvn_debugPortList[0]
            call MvnRunDebugProcess(l:port, l:envList)
        else
            let l:port= g:mvn_debugPortList[l:SelectedOption-1]
        endif

        "Execute the debugger.
        let l:debugger = "!xterm -T yavdb -e ".s:mvn_scriptDir."/bin/yavdb.sh "
        let l:debugger .= v:servername . " " . l:sourcepath ." " . l:port
        let l:debugger.= " |tee ".s:mvn_tmpdir."/dbgjdb.out &"
        exec l:debugger
    endif
endfunction; "}}}

function! MvnRunDebugProcess(port, envList) "{{{
    let l:classpath = a:envList[0]
    let l:sourcepath = a:envList[2]
    let l:isTest = a:envList[3]
    let l:classUnderDebug = MvnGetClassFromFilename(expand('%:p'))
    let l:output=""

    "Execute the java class or test runner.
    let l:javaProg = "!xterm  -T ".l:classUnderDebug
    let l:javaProg .= " -e ".s:mvn_scriptDir."/bin/run.sh "
    let l:javaProg .= " \"java -Xdebug -Xrunjdwp:transport=dt_socket"
    let l:javaProg .= ",address=".a:port.",server=y,suspend=y"
    if l:isTest
        let l:javaProg .= MvnGetJunitCmdString(l:classpath, l:classUnderDebug)
    else
        let l:javaProg .= " -classpath ".l:classpath
        let l:javaProg .= " ".l:classUnderDebug
    endif
    let l:javaProg .= "\" &"
    exec l:javaProg
endfunction; "}}}

function! MvnGetClassFromFilename(absoluteFilename) "{{{
"From the absolute java source file name determine the package class name.
    let l:srcFile = a:absoluteFilename
    let l:pos = matchend(l:srcFile, s:mvn_projectMainSrc.'/')
    if l:pos == -1
        let l:pos = matchend(l:srcFile, s:mvn_projectTestSrc.'/')
    endif
    if l:pos == -1
        echo "Error - No class."
        return ""
    endif
    let l:className = strpart(l:srcFile, l:pos)
    let l:pos = match(l:className, '.java$')
    if l:pos == -1
        echo "Error - No class."
        return ""
    endif
    let l:className = strpart(l:className, 0, l:pos)
    let l:className = substitute(l:className, '/', '.', 'g')
    return l:className
endfunction; "}}}
"}}} Debugging ----------------------------------------------------------------

"{{{ Javadoc/Sources ----------------------------------------------------------
function! MvnDownloadJavadoc() "{{{
"Download the javadoc using maven for the current project.
    let l:cmd = "mvn org.apache.maven.plugins:"
    let l:cmd .= "maven-dependency-plugin:2.1:"
    let l:cmd .= "resolve -Dclassifier=javadoc"
    echo system(l:cmd)
endfunction; "}}}

function! MvnDownloadJavaSource() "{{{
"Download the dependency source using maven for the current project.
    let l:cmd = "mvn org.apache.maven.plugins:"
    let l:cmd .= "maven-dependency-plugin:2.1:"
    let l:cmd .= "sources"
    echo system(l:cmd)
endfunction; "}}}

function! MvnOpenJavaDoc(javadocPath) "{{{
"Find the class under the cursor, locate the javadoc and open the html file with
"  lynx.
"javadocPath - the path to search for the documentation file.
"{{{ body
    call VjdeFindClassUnderCursor()
    let l:classname = g:vjde_java_cfu.class.name
    let l:classname= substitute(l:classname, "\\.", "/", "g")
    let l:docfile = l:classname  . ".html"
    echo l:docfile
    let l:tmpsuffixes = &suffixesadd
    set suffixesadd="html"
    let l:javadocPathList = split(a:javadocPath, ":")
    for tmpPath in l:javadocPathList
        let l:javadocfile = findfile(l:docfile, tmpPath)
        if strlen(l:javadocfile) > 0
            break
        endif
    endfor
    set suffixesadd=l:tmpsuffixes
    exec "!lynx ". l:javadocfile
endfunction; "}}} body }}}

function! MvnInstallJavadocFromSource(javadocParentDir, javaSourceParentDir,
        \unavailableJavadoc, unavailableSource) "{{{
"If the source exists build and install the javadoc.
"a:javadocParentDir - the installation directory for javadoc.
"a:javaSourceParentDir - the installation directory for source.
"a:unavailableJavadoc - unavailable javadoc jar list.
"a:unavailableSource - unavailable source jar list.
    let l:javadocPath = ''
    let l:srcToBuildList = []
    "test if the source is available to build the javadoc
    for javadocJar in a:unavailableJavadoc
        let l:tmpSrcJarName = substitute(javadocJar, "-javadoc.jar", "-sources.jar", "")
        let l:unavailable = 0
        for l:srcJarName in a:unavailableSource
            let l:unavailable = 0
            if l:srcJarName == l:tmpSrcJarName
                let l:unavailable = 1
            endif
        endfor
        if l:unavailable == 0
            call add(l:srcToBuildList, l:tmpSrcJarName)
        endif
    endfor
    "build javadoc from the source
    for srcJarName in l:srcToBuildList
        let l:dirName = MvnGetArtifactDirName(srcJarName, "sources")
        let l:newJavadocDir = a:javadocParentDir.'/'.l:dirName
        if !isdirectory(l:newJavadocDir)
            "find the package names in the source directory
            let l:findCmd = '`find '.a:javaSourceParentDir.'/'.l:dirName.
                \' -maxdepth 1 -type d -print`'
            let l:dirs = glob(l:findCmd)
            let l:dirList = split(l:dirs, '\n')
            let l:subpackages = ''
            for dir in l:dirList
                let dirPathList = split(dir, '/')
                let l:name = dirPathList[len(dirPathList)-1]
                let l:subpackages .= ' -subpackages '.l:name
            endfor
            let l:cmd = 'javadoc -linksource -sourcepath '.a:javaSourceParentDir.
                \'/'.l:dirName.' -d '.l:newJavadocDir.
                \l:subpackages
            call system(l:cmd)
         endif
         if len(l:javadocPath) > 0
             let l:javadocPath .= ':'
         endif
         let l:javadocPath .= l:newJavadocDir
    endfor
    return l:javadocPath
endfunction; "}}}

function! MvnInstallArtifactByClassifier(artifactPathParent, classJarLibPath, artifactType) "{{{
"Take the path to class jars and locate the associated artifact jars.
"Unpack the artifact jar for the class jars(if they exist) in the artifactPathParent.
"If the artifact is already unpacked then do nothing.
"artifactPathParent - the directory to contain the extracted artifacts, hopefully
"  one for each class jar.
"classJarLibPath - the class path containing class jars for which the associated
"  artifact type will be extracted.
"artifactType - javadoc or sources
"return list
"   [0] - a path of directories  of the existing and newly extracted artifact jars.
"   [1] - a list of the unavailable artifact jars.
"{{{ body
    let l:jarListList = MvnGetArtifactJarList(a:classJarLibPath, a:artifactType)
    let l:artifactJarList = jarListList[0]
    let l:unavailableJarList = jarListList[1]
    let l:artifactDirList = MvnGetArtifactDirList(l:artifactJarList, a:artifactPathParent, a:artifactType)
    let l:indx = 0
    let l:artifactPath = ""
    for dirname in l:artifactDirList
        if !isdirectory(dirname)
            call mkdir(l:dirname, "p")
            let l:jar = get(l:artifactJarList, l:indx)
            let l:unjarCmd = "cd " . l:dirname . "; jar -xvf " . l:jar
            call system(l:unjarCmd)
        endif
        if strlen(l:artifactPath) > 0
            let l:artifactPath .= ":"
        endif
        let l:artifactPath .= dirname
        let l:indx += 1
    endfor
    return [l:artifactPath, l:unavailableJarList]
endfunction; "}}} body }}}

function! MvnGetArtifactJarList(jarClassLibPath, artifactType) "{{{
"Take a classpath of class jars and create a list of jars of the associated
"  artifactType, if they exist.
"jarClassLibPath - pass g:vjde_lib_path
"artifactType - ie sources, javadoc
"return - a list of 2 lists.
"   [0] a list of jars of the requested artifactType.
"   [1] a list of the unavailable jars.
"{{{ body
"replaced by split   let l:binJarList = MvnGetListFromString(a:jarClassLibPath, ":")
    let l:binJarList = split(a:jarClassLibPath, ":")
    let l:indx = 0
    let l:artifactFileList= []
    let l:unavailableFileList = []
    for jar in l:binJarList
        if stridx(jar, ".jar") > 0
            let l:artifactFileName=  substitute(l:jar, ".jar$", "-".a:artifactType.".jar", "")
            let l:artifactFile = findfile(l:artifactFileName, "/")
            if strlen(l:artifactFile) > 0
                call add(l:artifactFileList, l:artifactFileName)
            else
                call add(l:unavailableFileList, l:artifactFileName)
            endif
        endif
        let l:indx += 1
    endfor
    return [l:artifactFileList, l:unavailableFileList]
endfunction; "}}} body }}}

function! MvnGetArtifactDirList(jarList, parentArtifactDir, artifactType) "{{{
"For a list of artifact jars, create a list of the names of directories
"  to extract them into.
"a:jarList - list of absolute names for artifact jars.
"a:parentArtifactDir - the parent directory of the extracted artifacts.
"a:artifactType - ie sources, javadoc
"return - list of absolute directories to extract the artifact into.
"{{{ body
    let l:dirList = []
    for jar in a:jarList
        let l:dirName = MvnGetArtifactDirName(l:jar, a:artifactType)
        call add(l:dirList, a:parentArtifactDir . "/" . l:dirName)
    endfor
    return l:dirList
endfunction; "}}} body }}}

function! MvnGetArtifactDirName(jarFilename, artifactType) "{{{
"For a jar file, create a simple directory name by stripping path and extension.
"a:jarFilename - absolute filename of a javadoc/sources jar.
"a:artifactType - ie sources, javadoc
"return - a simple directory name.
"{{{ body
    let l:jarName = matchstr(a:jarFilename, "[^/]\\+jar$")
    let l:jarDir = substitute(l:jarName, "-".a:artifactType.".jar$", "", "")
    return l:jarDir
endfunction; "}}} body }}}

function! MvnFindInherits(superclass) "{{{
"Search each tag file for implementors of the superclass.
"{{{ body
    let l:lineno = 1
    let g:inherits = []
    for l:tagfile in split(&tags,',')
        "match inherits:superclass,cl  inherits:cl,superclass  etc
        "/inherits:\(Plunk\|.\+,Plunk\)\(,\|$\|\s\)
        let l:cmd = "grep 'inherits:\\(".a:superclass
        let l:cmd .= "\\|.\\+,".a:superclass."\\)\\(,\\|$\\|\\s\\)' ".l:tagfile
        "let l:cmd = "grep 'inherits:.*".a:superclass.".*$' ". l:tagfile
        let l:tagMatches = system(l:cmd)
        if strlen(l:tagMatches) > 0
            for l:line in split(l:tagMatches, "\n")
                call add(g:inherits, l:lineno.":".l:line)
                let l:lineno += 1
            endfor
        endif
    endfor
    call MvnPickInherits()
endfunction; "}}} body }}}

function! MvnPickInherits()  "{{{
"Show the list of subclasses from the MvnFindInherits search.
"{{{ body
    if len(g:inherits) > 0
        call inputsave()
        let l:lineNo = inputlist(g:inherits)
        call inputrestore()
        if l:lineNo > 0
            let l:itag = g:inherits[l:lineNo-1]
            let l:startPos = match(l:itag, ':') + 1
            let l:endPos = match(l:itag, '\s')
            let l:etag = strpart(l:itag, l:startPos, l:endPos - l:startPos)
            call feedkeys(":tag ".l:etag." \<CR>")
        endif
    else
        echo "No subclass found."
    endif
endfunction; "}}} body }}}

function! MvnGetTagFileDir(srcPath, prjPomDict) "{{{
"Return the tag filename for the source directory.
"{{{ body
    let l:tagFilename = a:srcPath.'/tags'
    if has_key(a:prjPomDict, 'home') && has_key(a:prjPomDict, 'srcMain')
        let l:homeDir = a:prjPomDict['home']
        let l:srcDir = a:prjPomDict['srcMain']
        let l:pos = matchend(a:srcPath, l:srcDir)
        if l:pos == len(a:srcPath)
            let l:tagFilename = l:homeDir . "/tags"
        elseif has_key(a:prjPomDict, 'srcTest')
            let l:srcPath = a:prjPomDict['srcTest']
            let l:pos = matchend(a:srcPath, l:srcPath)
            if l:pos == len(a:srcPath)
                let l:tagFilename = l:homeDir . "/tags-t"
            endif
        endif
    endif
    return l:tagFilename
endfunction; "}}} body }}}

function! MvnBuildTags(currentPrjId, srcPathList, srcPrjIdList, prjIdPomDict ) "{{{
"Build tag files for 3 different source types. Don't build the tag files for
"sibling projects, just add the tag file to the path.
"a:currentPrjId the id of the current project.
"a:srcPathList a list of directories to tag.
"a:srcPrjIdList a list of project identifiers for tagging main source.
"a:prjIdPomDict - project configuration store, see MvnSetPrjIdPomDict().
"{{{ body
    let l:tagPath = ""
    for dir in split(a:srcPathList, ':')
        let l:tagfile = dir."/tags"
        let l:isOldTag = 1
        if filereadable(l:tagfile)
            if getftime(l:tagfile) > getftime(dir)
                let l:isOldTag = 0
            endif
        endif
        if l:isOldTag
            call MvnCreateTagFile(l:tagfile, dir)
        endif
        if strlen(l:tagPath) > 0
            let l:tagPath .= ","
        endif
        let l:tagPath .= l:tagfile
    endfor
    for prjId in a:srcPrjIdList
        let l:srcDir = a:prjIdPomDict[prjId]['srcMain']
        let l:tagfile = a:prjIdPomDict[prjId]['home'].'/tags'
        if prjId == a:currentPrjId
            call MvnCreateTagFile(l:tagfile, l:srcDir)
        endif
        if strlen(l:tagPath) > 0
            let l:tagPath .= ","
        endif
        let l:tagPath .= l:tagfile
    endfor
    if len(a:currentPrjId) > 0
        let prjId = a:currentPrjId
        let l:srcDir = a:prjIdPomDict[a:currentPrjId]['srcTest']
        let l:tagfile = a:prjIdPomDict[a:currentPrjId]['home'].'/tags-t'
        call MvnCreateTagFile(l:tagfile, l:srcDir)
        if strlen(l:tagPath) > 0
            let l:tagPath .= ","
        endif
        let l:tagPath .= l:tagfile
    endif
    return l:tagPath
endfunction; "}}} body }}}

function! MvnCreateTagFile(tagFilename, sourceDir) "{{{
    let l:cmd = s:mvn_tagprg." --fields=+m+i --recurse=yes ".
        \"-f ".a:tagFilename." ".a:sourceDir
    call system(l:cmd)
endfunction; "}}}

function! MvnTagCurrentFile() "{{{
"Build the tags for the current file and append to the tag file.
"{{{ body
    let l:srcDir = expand("%:p:h")
    if !exists("g:mvn_currentPrjDict['home']") || len(g:mvn_currentPrjDict['home']) == 0
        throw "No g:mvn_currentPrjDict['home']."
    endif
    let l:tagFilename = MvnGetTagFileDir(l:srcDir, g:mvn_currentPrjDict)
    "Remove all existing tags for the file.
    let l:cleanCmd ="( echo \"g^".expand("%:p")
    let l:cleanCmd .="^d\" ; echo 'wq' ) | ex -s ".l:tagFilename
    call system(l:cleanCmd)
    let l:cmd = s:mvn_tagprg." -a --fields=+m+i --recurse=yes ".
        \"-f ".l:tagFilename." ".expand("%:p")
    call system(l:cmd)
endfunction; "}}} body }}}

function! MvnFindJavaClass() "{{{
"Find a class in the jars in the maven repo.
"{{{ body
    call inputsave()
    let l:pattern = input("Enter the class name:")
    call inputrestore()
    let l:jarFilesList = split(system("find ~/.m2 -name \"*.jar\""), "\n")
    let l:matches = ""
    for jar in l:jarFilesList
        let l:result = system("jar -tvf ".jar."|grep ".l:pattern)
        if strlen(l:result) > 0
             echo(jar.": ".l:result."\n")
        endif
    endfor
endfunction; "}}} body }}}
"}}} Javadoc/Sources ----------------------------------------------------------

"{{{ Junit --------------------------------------------------------------------
function! MvnGetJunitCmdString(classpath, testClass) "{{{
"Build the junit command string.
   return " -classpath ".a:classpath." junit.textui.TestRunner ". a:testClass
endfunction; "}}}

function! MvnRunJunit() "{{{
"Run test add errors to quickfix list.
"{{{ body
    let l:envList = MvnTweakEnvForSrc(expand('%:p'))
    if empty(l:envList)
        return -1
    endif
    let l:classpath = l:envList[0]
    let l:testClass = MvnGetClassFromFilename(expand('%:p'))
    if strlen(l:testClass) == 0
        return -1
    endif
    let l:junitCmd = MvnGetJunitCmdString(l:classpath, l:testClass)
    let l:cmd = "!java ". l:junitCmd
    let l:cmd = l:cmd." | tee ".s:mvn_tmpdir."/junit.out"
    exec l:cmd
    let l:testOutput = readfile(s:mvn_tmpdir."/junit.out")
    let l:ctr = 0
    let l:errorSize = len(l:testOutput)
    let l:quickfixList = []
    while l:ctr < l:errorSize
        let l:line = l:testOutput[l:ctr]
        let l:pos = matchend(l:line,'^\d\+) [^:]\+:')
        if l:pos > -1
            let l:errorMessage = strpart(l:line, l:pos)
            let l:ctr += 1
            if l:ctr < l:errorSize
                let l:line = l:testOutput[l:ctr]
                let l:pos = matchend(l:line, '^\s\+[^:]\+:')
                let l:line = strpart(l:line, l:pos)
                let l:pos = matchend(l:line, ')')
                let l:lineno = strpart(l:line, 0, l:pos)
                if match(l:lineno, '\d+')
                    let l:qfixLine = {'lnum': l:lineno, 'bufnr': bufnr(""),
                        \'col': 0, 'valid': 1, 'vcol': 1, 'nr': -1, 'type': 'E',
                        \'pattern': '', 'text': l:errorMessage }
                    call add(l:quickfixList, l:qfixLine)
                endif
            endif
        endif
        let l:ctr += 1
    endwhile
    if len(l:quickfixList) > 0
        call setqflist(l:quickfixList)
        cl
    endif
endfunction; "}}} body }}}
"}}} Junit --------------------------------------------------------------------

"{{{ Tests --------------------------------------------------------------------
"{{{ TestRunnerObject ---------------------------------------------------------
let s:TestRunner = {}
function! s:TestRunner.New() "{{{
    let l:testRunner = copy(self)
    let l:testRunner.testCount = 0
    let l:testRunner.passCount = 0
    let l:testRunner.failCount = 0
    let l:testRunner.startTime = localtime()
    return l:testRunner
endfunction "}}}
function! s:TestRunner.AssertEquals(failMessage, expected, result) "{{{
    let self.testCount += 1
    let l:fail = 1
    if type(a:expected) == type("")
        if string(a:expected) == string(a:result)
            let l:fail = 0
        endif
    elseif a:expected == a:result
        let l:fail = 0
    endif
    if l:fail
        let self.failCount += 1
        let l:testResult = printf("%s",
            \"\n-EXPECTED ".string(a:expected)).
            \"\n-GOT      ".printf("'%s'",string(a:result))
        echo a:failMessage.l:testResult
    else
        let self.passCount += 1
    endif
endfunction "}}}
function! s:TestRunner.PrintStats() "{{{
    let l:result = "Total Tests:".printf("%d",self.testCount)
    let l:result .= " Pass:".printf("%d",self.passCount)
    let l:result .= " Fail:".printf("%d",self.failCount)
    let l:seconds = localtime() - self.startTime
    let l:result .= "\nCompleted in " . string(l:seconds) . " seconds."
    echo l:result
endfunction "}}}
"}}} TestRunnerObject ---------------------------------------------------------
function! s:TestPluginObj(testR) "{{{ TestPluginObj
"Test object operation.
    let l:jPlugin1 = s:JunitPlugin.New()
    call l:jPlugin1.addStartRegExp('reg1')
    let l:jPlugin2 = s:JunitPlugin.New()
    call l:jPlugin2.addStartRegExp('reg2')
    call a:testR.AssertEquals('TestPluginObj junit plugin fail:', 'reg1',
           \ get(l:jPlugin1._startRegExpList, 0))
    call a:testR.AssertEquals('TestPluginObj junit plugin fail:', 'reg2',
           \ get(l:jPlugin2._startRegExpList, 0))
endfunction "}}} TestPluginObj
function! s:TestMvn2Plugin(testR) "{{{ TestMvn2Plugin
    let l:maven2TestFile = s:mvn_scriptDir.'/plugin/test/maven2.out'
    let l:testList = readfile(l:maven2TestFile)
    let l:mvn2Plugin = s:Mvn2Plugin.New()
    call l:mvn2Plugin.setOutputList(l:testList)
    let l:errorsDict = l:mvn2Plugin.processAtLine(11)
    call a:testR.AssertEquals('mvn2 lineNumber in compiler output:', 20, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn2 Source file rowNum:', 39, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('mvn2 Source file colNum:', 0, l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('mvn2 Error message::', 'illegal start of type', l:errorsDict.quickfixList[0].text)
endfunction "}}} TestMvn2Plugin
function! s:TestMvn3Plugin(testR) "{{{ TestMvn3Plugin
    let l:maven3TestFile = s:mvn_scriptDir.'/plugin/test/maven3.out'
    let l:testList = readfile(l:maven3TestFile)
    let l:mvn3Plugin = s:Mvn3Plugin.New()
    call l:mvn3Plugin.setOutputList(l:testList)
    let l:errorsDict = l:mvn3Plugin.processAtLine(16)
    call a:testR.AssertEquals('mvn3 lineNumber in compiler output:', 19, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn3 Source file rowNum:', 9, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('mvn3 Source file colNum:', 1, l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('mvn3 Error message::', '<identifier> expected', l:errorsDict.quickfixList[0].text)
    let l:errorsDict = l:mvn3Plugin.processAtLine(17)
    call a:testR.AssertEquals('mvn3 lineNumber in compiler output:', 17, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn3 quickfix list size:', 0, len(l:errorsDict.quickfixList))
endfunction "}}} TestMvn3Plugin
function! s:TestJunitPlugin(testR) "{{{ TestJunitPlugin
    let l:testFile = s:mvn_scriptDir.'/plugin/test/maven3junit3.out'
    let l:testList = readfile(l:testFile)
    let l:junit3Plugin = s:Junit3Plugin.New()
    call l:junit3Plugin.setOutputList(l:testList)
    let l:errorsDict = l:junit3Plugin.processAtLine(35)
    call a:testR.AssertEquals('junit3 lineNumber :', 69, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('junit3 error count:', 3, len(l:errorsDict.quickfixList))
    call a:testR.AssertEquals('junit3 Source file rowNum:', 35, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('junit3 Source file colNum:', '', l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('junit3 Error message::', 'java.lang.ArithmeticException: / by zero', l:errorsDict.quickfixList[0].text)
endfunction "}}} TestJunitPlugin
function! s:TestCheckStylePlugin(testR) "{{{ TestCheckStylePlugin
    let l:checkStyleTestFile = s:mvn_scriptDir.'/plugin/test/checkstyle.out'
    let l:testList = readfile(l:checkStyleTestFile)
    let l:checkStylePlugin = s:CheckStylePlugin.New()
    call l:checkStylePlugin.setOutputList(l:testList)
    let l:errorsDict = l:checkStylePlugin.processAtLine(44)
    call a:testR.AssertEquals('checkstyle lineNumber in compiler output:', 110, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('checkstyle Source file rowNum:', 37, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('checkstyle Source file colNum:', 37, l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('checkstyle Error message::', 'Variable ''consecutiveCount'' should be declared final.', l:errorsDict.quickfixList[0].text)
    let l:checkStyleTestFile = s:mvn_scriptDir.'/plugin/test/checkstyle1.out'
    let l:testList = readfile(l:checkStyleTestFile)
    call l:checkStylePlugin.setOutputList(l:testList)
    let l:errorsDict = l:checkStylePlugin.processAtLine(47)
    call a:testR.AssertEquals('checkstyle lineNumber in compiler output:', 48, l:errorsDict.lineNumber)
endfunction "}}} TestCheckStylePlugin
function! s:TestProjTreeBuild(testR) "{{{ TestProjTreeBuild
    let l:prjLocation= s:mvn_scriptDir.'/plugin/test/proj'
    let l:pomList = [l:prjLocation.'/test/pom.xml']
    let l:prjIdPomDict = {}
    let l:prjTreeTxt= MvnBuildProjectTree(l:pomList, l:prjIdPomDict)
    call a:testR.AssertEquals('TestProjTreeBuild ::', 2, len(l:prjTreeTxt))
    "TODO add test for l:prjIdPomDict and in.vim.

    let l:prjIdPomDict = {}
    let l:pomList = [l:prjLocation.'/parent/pom.xml',
    \ l:prjLocation.'/parent/test1/pom.xml',
    \ l:prjLocation.'/parent/test2/pom.xml',
    \ l:prjLocation.'/parent/test3/pom.xml']
    let l:result = MvnBuildProjectTree(l:pomList, l:prjIdPomDict)
    "TODO add test for l:prjIdPomDict and in.vim.
    "call writefile(l:result.prjTreeTxt, '/tmp/mvn.txt')
endfunction "}}} TestProjTreeBuild
function! s:TestMvnIsInList(testR) "{{{ TestMvnIsInList
"Test object operation.
    let l:ret = MvnIsInList(['a', 'b', 'c'], "a")
    call a:testR.AssertEquals('MvnIsInList1: ', 1, l:ret)
    let l:ret = MvnIsInList(['a', 'b', 'c'], "d")
    call a:testR.AssertEquals('MvnIsInList2: ', 0, l:ret)
endfunction "}}} TestMvnIsInList
function! s:TestEnvBuild(testR) "{{{ TestEnvBuild
"Test the generation of the project tree.
    new
    let l:mvn_testPrj = s:mvn_scriptDir."/plugin/test/proj/test1"
    let l:testProjDir = s:mvn_tmpdir."/mvn-ide-test"
    call system("mkdir -p ".l:testProjDir)
    call system("cp -a ".l:mvn_testPrj." ".l:testProjDir)
    let l:testHome = l:testProjDir."/test1"
    call MvnInsertProjectTree(l:testHome)
    "Test with the custom in.vim configuration.
    call a:testR.AssertEquals('Mvn src location: ', ' srcMain=src/m/java {', getline(3))
    call a:testR.AssertEquals('Mvn test src location: ', ' srcTest=src/t/java {', getline(11))
    call a:testR.AssertEquals('Mvn main resource location: ', ' resrcMain=src/m/r {', getline(15))
    call a:testR.AssertEquals('Mvn test resource location: ', ' resrcTest=src/t/r {', getline(17))
    call a:testR.AssertEquals('Sibling project identifiers: ',
            \"#PROJECT_IDS={'test:test1:1.0':".
            \" '/tmp/mvn-ide-test/test1'}", getline(20))
    "Check the tag path configuration in in.vim, too hard to test the rest.
    :2
    let l:currentDir = getcwd()
    exec 'cd '.l:testHome
    call MvnBuildEnv(l:testHome)
    exec 'cd '.l:currentDir
    let l:inVimList = readfile(l:testHome.'/in.vim')
    call a:testR.AssertEquals('Test in.vim tags',
        \'let &tags="'.l:testHome.'/tags,'.g:mvn_javaSourceParentDir.
        \'/junit-3.8.2-sources/tags,'.g:mvn_additionalJavaSourcePath.'/tags"',
        \get(l:inVimList, 0))
    call a:testR.AssertEquals('Test in.vim path',
        \'let &path="'.l:testHome.'/src/m/java/**,'.g:mvn_javaSourceParentDir.
        \'/junit-3.8.2-sources/**,'.g:mvn_additionalJavaSourcePath.'/**,'.
        \l:testHome.'/src/t/java/**"',
        \get(l:inVimList, 1))
    call a:testR.AssertEquals('Test in.vim source path',
        \'let g:mvn_javaSourcePath="'.l:testHome.'/src/m/java:'.g:mvn_javaSourceParent.
        \'/junit-3.8.2-sources:'.g:mvn_additionalJavaSourcePath.'"',
        \get(l:inVimList, 2))
    call a:testR.AssertEquals('Test in.vim javadoc path',
        \'let g:mvn_javadocPath="'.g:mvn_javadocParentDir.
        \'/junit-3.8.2-javadoc:'.g:mvn_additionalJavadocPath.'"',
        \get(l:inVimList, 3))
    "g:vjde_lib_path ie classpath test difficult so test MvnGetJreRuntimeLib()
    call a:testR.AssertEquals('Test MvnGetJreRuntimeLib()',
        \1, filereadable(MvnGetJreRuntimeLib()))
    call a:testR.AssertEquals('Test in.vim projectHome',
        \'let g:mvn_currentPrjDict="'.{}.'"',
        \get(l:inVimList, 5))
    "TODO test in.vim for the project id entry.
    bd!
    call system("rm -rf ".l:testHome)
endfunction "}}} TestEnvBuild
function! s:TestCreatePomDict(testR) "{{{ TestCreatePomDict
    let l:testPrj = s:mvn_scriptDir."/plugin/test/proj/test1"
    let l:mvnFileData = MvnGetPomFileData(l:testPrj)
    let l:mvnPomDict =  MvnCreatePomDict(l:mvnFileData, l:testPrj, {})
    let l:dependencies = l:mvnPomDict['dependencies']
    call a:testR.AssertEquals('CreatePomDict home: ',
        \l:testPrj, l:mvnPomDict['home'])
    call a:testR.AssertEquals('CreatePomDict dependencies: ',
            \['junit:junit:3.8.2'], l:dependencies)
    call a:testR.AssertEquals('CreatePomDict srcMain: ',
        \l:testPrj.'/src/m/java', l:mvnPomDict['srcMain'])
    call a:testR.AssertEquals('CreatePomDict srcTest: ',
        \l:testPrj.'/src/t/java', l:mvnPomDict['srcTest'])
    call a:testR.AssertEquals('CreatePomDict classMain: ',
        \l:testPrj.'/t/classes', l:mvnPomDict['classMain'])
    call a:testR.AssertEquals('CreatePomDict classTest: ',
        \l:testPrj.'/t/test-classes', l:mvnPomDict['classTest'])
    call a:testR.AssertEquals('CreatePomDict resrcMain: ',
        \[l:testPrj.'/src/m/r'], l:mvnPomDict['resrcMain'])
    call a:testR.AssertEquals('CreatePomDict resrcTest: ',
        \[l:testPrj.'/src/t/r'], l:mvnPomDict['resrcTest'])
endfunction "}}} TestCreatePomDict
function! s:TestGetPomDetailDict(testR) "{{{
    new
    let l:mvn_testPrj = s:mvn_scriptDir."/plugin/test/proj/test1"
    let l:testProjDir = s:mvn_tmpdir."/mvn-ide-test"
    call system("mkdir -p ".l:testProjDir)
    call system("cp -a ".l:mvn_testPrj." ".l:testProjDir)
    let l:testHome = l:testProjDir."/test1"
    call MvnGetPrjPomDict(l:testHome)
endfunction "}}}
function! s:TestMvnGetXPathFromTxt(testR) "{{{ TestMvnGetXPathFromTxt
    let l:nodes = []
    let l:rawnodes = MvnGetXPathFromTxt('<a><b><c>foo</c><c>bar</c></b></a>', '/a/b/*/text\(\)')
    let l:nodes = MvnParseNodesToList(l:rawnodes)
    call a:testR.AssertEquals('MvnGetXPathFromTxt1: ', ['foo', 'bar'], l:nodes)
endfunction "}}} TestMvnGetXPathFromTxt
function! s:TestMvnGetXPath(testR) "{{{ TestMvnGetXPath
    let l:nodes = []
    let l:xmlFile = s:mvn_scriptDir."/plugin/test/xml/test.xml"
    let l:rawnodes = MvnGetXPath(l:xmlFile, '/a/b/c/text\(\)')
    let l:nodes = MvnParseNodesToList(l:rawnodes)
    call a:testR.AssertEquals('MvnGetXPathFromTxt1: ', ['foo', 'bar'], l:nodes)

    let l:pomFilename = s:mvn_scriptDir."/plugin/test/xml/effective-pom.xml"
    let l:srcMainQuery = "/project/build/sourceDirectory/text\(\)"
    let l:rawNodeList = MvnGetXPath(l:pomFilename, l:srcMainQuery)
    call a:testR.AssertEquals('MvnGetXPathFromPom1: ', 'Found 1',
        \strpart(l:rawNodeList[0], 0, 7))
    call a:testR.AssertEquals('MvnGetXPathFromPom2: ', '-- NODE --',
        \l:rawNodeList[1])
    call a:testR.AssertEquals('MvnGetXPathFromPom3: ',
        \'/usr/home/daren/.vim/bundle/maven-ide/plugin/test/proj/test1/src/m/java',
        \l:rawNodeList[2])
    let l:nodeList = MvnParseNodesToList(l:rawNodeList)
    call a:testR.AssertEquals('ParseSrcNodes: ',
        \"/usr/home/daren/.vim/bundle/maven-ide/plugin/test/proj/test1/src/m/java",
        \l:nodeList[0])
endfunction "}}} TestMvnGetXPath
function! s:TestGetPomId(testR) "{{{ TestMvnGetPomId
    let l:effectivePom = s:mvn_scriptDir."/plugin/test/xml/effective-pom.xml"
    let l:id = MvnGetPomId(l:effectivePom)
    call a:testR.AssertEquals('MvnGetPomId: ', 'test:test1:1.0', l:id)
endfunction "}}} TestMvnGetPomId
function! s:TestGetVimInDict(testR) "{{{ TestMvnVimInDict
    let l:invim= s:mvn_scriptDir."/plugin/test/test_in.vim"
    let l:projectDict = MvnLoadPrjPomDict(l:invim)
    call a:testR.AssertEquals('MvnVimInDict: ', {'id': 'test:test:1.0'}, l:projectDict)
endfunction "}}}
function! s:TestIdFromJarName(testR) "{{{
    let l:testJarName = '/.m2/repository/org/dbunit/dbunit/2.4.2/dbunit-2.4.2.jar'
    let l:id = MvnIdFromJarName(l:testJarName)
    call a:testR.AssertEquals('MvnIdFromJarName: ', 'dbunit:dbunit:2.4.2', l:id)
endfunction "}}}
function! s:TestClasspathPreen(testR) "{{{
   let l:testCP= '/.m2/repository/org/dbunit/dbunit/2.4.2/dbunit-2.4.2.jar:/foobar.jar'
   let l:preened = MvnClasspathPreen(['dbunit:dbunit:2.4.2'], l:testCP)
   call a:testR.AssertEquals('ClasspathPreen: ', '/foobar.jar', l:preened)
endfunction; "}}}
function! s:TestInstallJavadocFromSource(testR) "{{{
    :let s:mvn_tmpdir = "/tmp"
    "test the find command
    let l:findCmd = "`find ".s:mvn_scriptDir."/plugin/test/javadoc/src/mvn-ide-test".
        \" -maxdepth 1 -type d -print`"
    let l:dirs = glob(l:findCmd)
    let l:dirList = split(l:dirs, '\n')
    let l:subDirs = []
    for dir in l:dirList
        let l:segList = split(dir, '/')
        call add(l:subDirs, l:segList[len(l:segList)-1])
    endfor
    call a:testR.AssertEquals('MvnInstallJavadoc test find: ', ['mvn-ide-test', 'mvnidetest', 'META-INF'], l:subDirs)

    for dir in l:dirList
        let dirPathList = split(dir, '/')
        let l:name = dirPathList[len(dirPathList)-1]
        call add(l:subDirs, l:name)
    endfor
    "test the build of javadoc
    call system('mkdir -p '. s:mvn_tmpdir.'/mvn-ide-test/javadoc')
    let l:jdPath = MvnInstallJavadocFromSource(s:mvn_tmpdir.'/mvn-ide-test/javadoc',
        \s:mvn_scriptDir.'/plugin/test/javadoc/src',
        \['/blah/blah/mvn-ide-test-sources.jar'], [])
    call a:testR.AssertEquals('MvnInstallJavadoc: ', s:mvn_tmpdir.'/mvn-ide-test/javadoc/mvn-ide-test',
        \l:jdPath)

endfunction; "}}}
function! s:TestDependencies(dummy) "{{{
    let l:xpathFile = glob("`which xpath`")  
    if !filereadable(l:xpathFile)
        throw "No xpath executable. Check maven-ide installation instructions."
    endif
endfunction; "}}}
function! MvnRunTests() "{{{ MvnRunTests
    let l:testR = s:TestRunner.New()
    "{{{ misc tests
    call s:TestDependencies(l:testR)
    call s:TestMvnIsInList(l:testR)
    "}}} misc tests
    "{{{ plugin tests
    call s:TestPluginObj(l:testR)
    call s:TestMvn2Plugin(l:testR)
    call s:TestMvn3Plugin(l:testR)
    call s:TestCheckStylePlugin(l:testR)
    call s:TestJunitPlugin(l:testR)
    "}}} plugin tests
    "{{{ Tree/Env Build
    call s:TestProjTreeBuild(l:testR)
    call s:TestCreatePomDict(l:testR)
    call s:TestGetPomId(l:testR)
    call s:TestGetVimInDict(l:testR)
    call s:TestIdFromJarName(l:testR)
    call s:TestClasspathPreen(testR)
    call s:TestInstallJavadocFromSource(testR)
    "}}} Tree/Env Build
    "{{{ MvnGetClassFromFilename
    let l:result = MvnGetClassFromFilename("/opt/proj/src/main/java/pack/age/Dummy.java")
    call l:testR.AssertEquals('MvnTweakEnvForSrc fail:', "pack.age.Dummy", l:result)
    "}}} MvnGetClassFromFilename
    "{{{ xml tests
    call s:TestMvnGetXPath(l:testR)
    call s:TestMvnGetXPathFromTxt(l:testR)
    "}}} xml tests
    call l:testR.PrintStats()
endfunction; "}}} MvnRunTests
function! MvnRunSingleTest(testFuncName) "{{{ MvnCallTest
"Useful during test development.
"a:testFuncName - a string containing the script function name of the test
"   function without the 's:' prefix.
    let l:testR = s:TestRunner.New()
    let TestFun = function('s:'.a:testFuncName)
    call TestFun(l:testR)
    call l:testR.PrintStats()
endfunction; "}}} MvnCallTest
"}}} Tests --------------------------------------------------------------------

"{{{ Coding -------------------------------------------------------------------
function! MvnCodeFormat() "{{{ 2
"Format the current file.
"{{{ 3
    let save_cursor = getpos(".")
    "Remove all end of line spaces.
    :1,$:s/ \+$//g
    call setpos('.', save_cursor)
endfunction; "}}} 3 }}} 2
"}}} Coding -------------------------------------------------------------------

"{{{ Key mappings -------------------------------------------------------------
map \cf :call MvnCodeFormat() <RETURN>
map \rm :call MvnCompile() <RETURN>
map \rj :call MvnJavacCompile() <RETURN>
map \rd :call MvnDoDebug() <RETURN>
map \rt :call MvnRunJunit() <RETURN>
map \rp :call MvnRefreshPrjIdPomDict() <RETURN>
map \sd :call MvnOpenJavaDoc(g:mvn_javadocPath) <RETURN>
map \dd :call MvnDownloadJavadoc() <RETURN>
map \ds :call MvnDownloadJavaSource() <RETURN>
map \be :call MvnBuildEnvSelection() <RETURN>
map \bp :call MvnInsertProjectTree("") <RETURN>
map \bt :call MvnTagCurrentFile() <RETURN>
map \fc :call MvnFindJavaClass() <RETURN>
map \gs :call MvnFindInherits(expand("<cword>")) <RETURN>
map \ps :call MvnPickInherits() <RETURN>
"}}} Key mappings -------------------------------------------------------------

"{{{ Public Variables ---------------------------------------------------------
set cfu=VjdeCompletionFun
"let g:vjde_lib_path = generated into in.vim
"let g:mvn_currentPrjDict = generated into in.vim
"let g:mvn_javadocPath = generated into in.vim
"let g:mvn_javaSourcePath = generated into in.vim

if !exists('g:mvn_javadocParentDir')
    let g:mvn_javadocParentDir = "/opt/work/javadoc"
endif
if !exists('g:mvn_javaSourceParentDir')
    let g:mvn_javaSourceParentDir = "/opt/work/javasource"
endif
if !exists('g:mvn_additionalJavadocPath')
    let g:mvn_additionalJavadocPath = "/opt/work/javadoc/jdk-6u30-apidocs/api"
endif
if !exists('g:mvn_additionalJavaSourcePath')
    let g:mvn_additionalJavaSourcePath = "/opt/work/javasource/openjdk6-b24_4"
endif
if !exists('g:mvn_javaSrcFilterList')
    let g:mvn_javaSrcFilterList = ["*.java", "*.html", "*.js", "*.jsp"]
endif
if !exists('g:mvn_resourceFilterList')
    let g:mvn_resourceFilterList = ["*.vim", "*.xml", "*.properties", ".vjde"]
endif
if !exists('g:mvn_mavenType')
    let g:mvn_mavenType = "maven3"
endif
if !exists('g:mvn_debugPortList')
    let g:mvn_debugPortList = [8888,11550]
endif
if !exists('g:mvn_pluginList')
    let g:mvn_pluginList = ['Mvn3Plugin', 'Junit3Plugin', 'CheckStylePlugin']
endif
if !exists('g:mvn_compilerVersion')
    let g:mvn_compilerVersion = '2.5'
endif
"{{{ Private Variables --------------------------------------------------------
function! s:MvnDefaultPrjEnvVars()
    let s:mvn_projectMainWebapp="src/main/webapp"
endfunction
call s:MvnDefaultPrjEnvVars()

let s:mvn_projectMainSrc="src/main/java"
let s:mvn_projectTestSrc="src/test/java"
let s:mvn_projectMainClasses="target/classes"
let s:mvn_projectTestClasses="target/test-classes"
let s:mvn_projectMainResources="src/main/resources"
let s:mvn_projectTestResources="src/test/resources"
let s:mvn_projectMainWebapp="src/main/webapp"

let s:mvn_kernel = matchstr(system("uname -s"), '\w\+')
if s:mvn_kernel =~ "FreeBSD"
   let s:mvn_xpathcmd = "xpath filename \"query\""
   let s:mvn_tagprg = "exctags"
elseif s:mvn_kernel == "Linux"
   let s:mvn_xpathcmd = "xpath -e \"query\" filename"
   let s:mvn_tagprg = "ctags"
endif
let s:mvn_tmpdir = "/tmp"
let s:mvn_defaultProject = ""
let s:mvn_scriptFile = expand("<sfile>")
let s:mvn_scriptDir = strpart(s:mvn_scriptFile, 0,
        \ match(s:mvn_scriptFile, "/plugin/"))
let s:plugins = MvnPluginInit()
"}}} Private Variables  -------------------------------------------------------
"}}} Public Variables ---------------------------------------------------------

"vim:ts=4 sw=4 expandtab tw=78 ft=vim fdm=marker:
