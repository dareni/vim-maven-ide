"=============================================================================
" File:        maven-ide.vim
" Author:      Daren Isaacs (ikkyisaacs at gmail.com)
" Last Change: Sat Dec 29 15:54:33 EST 2012
" Version:     0.6
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
        "-1 get all projects from cursor to buffer end.
        let l:projectCount = -1
    endif

    "Quick check for valid start project, is thrown away and refound at
    "the start of the while loop. Should be fixed for efficiency.
    let l:projectDir = MvnGetProjectDir(l:save_cursor[1])
    if !strlen(l:projectDir) > 0
        echo("Error - Current line is not a project header!")
        return l:projectDirList
    endif
    let l:onlyCountParents = 1
    if 0 == match(getline(l:save_cursor[1]), "^\\s")
        "If the processing starts on a non parent ie subproject we
        "want to count child and parent projects.
        let l:onlyCountParents = 0
    endif

    "Get all the selected project directories from the project buffer.
    while !l:finish
        let l:projectLineNo = search(l:prjRegExp, 'Wc')
        if l:projectLineNo == 0
            let l:finish = 1
        else
            let l:exception = ''
            try
                let l:projectDir = MvnGetProjectDir(l:projectLineNo)
            catch /^MvnGetProjectDir:/
                "Add this catch for when a broken project exists as the
                "first project after a selection. When the broken project
                "exists outside the select we do not want to break processing.
                "ie The first parent project after a selection of parents or
                "the end of buffer is the end marker for project searching.
                if l:projectCount != -1 && l:counter == l:projectCount &&
                    \l:onlyCountParents == 1
                    let l:exception = v:exception
                else
                    throw v:exception
                endif
            endtry
            if strlen(l:projectDir) > 0 || strlen(l:exception) > 0
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
"a:projectLineNo - the line number of the project header.
"{{{ body
    let l:line = getline(a:projectLineNo)
    let l:projectDir = matchstr(l:line, '=\@<=\([/A-Za-z0-9._-]\+\)', 0, 1)
    if !strlen(l:projectDir) > 0
        throw "MvnGetProjectDir: No project dir for: ". l:line
    endif
    if !filereadable(l:projectDir."/pom.xml")
        throw "MvnGetProjectDir: ".l:projectDir."/pom.xml"." Not readable."
    endif
    return l:projectDir
endfunction; "}}} body }}}

function! MvnInsertProjectTree(projPath) "{{{
"Build the project tree text for a maven project.
"a:projPath - non empty string turns off the prompt for unit test.
    let l:prjIdPomFilename = MvnGetPrjIdPomFilename(1)
    if strlen(a:projPath) > 0
        let l:mvnProjectPath= a:projPath
    else
        if strlen(s:mvn_defaultProject) == 0
            let s:mvn_defaultProject = matchstr(system("pwd"), "\\p\\+")
        endif
        call inputsave()
        let l:mvnProjectPath = input("Enter the maven project path:", s:mvn_defaultProject, "file")
        call inputrestore()
    endif
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
    let l:tmpPomList = split(system(l:cmd))
    let l:pomList = MvnPomFileOrdering(l:tmpPomList)

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
"current buffer. On completion use Project \R to populate with files.
"a:pomList - build a project tree for each pom.xml in the list.
"a:prjIdPomDict - project configuration store, see MvnSetPrjIdPomDict().
"return - prjTreeLinesList - a list containing the new text representing the project to
"   display in the project tree.
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

function! MvnJumpToTree() "{{{
"Jump to the position in the tree for the current file.
"{{{ body
    let l:absoluteFilename = expand('%:p')
    let l:filename = expand('%:t')
    if !exists('g:proj_running')
        throw "Is project running? Activate with ':Project'."
    endif

    let l:save_buffer = bufnr('.')
    let l:prjWindow = bufwinnr(g:proj_running)
    exe l:prjWindow.'wincmd w'
    let l:save_cursor = getpos('.')

    call setpos('.', [0, 1, 1, 0])
    let l:lineno = 1
    let l:foundLine = -1
    while l:lineno > 0 && l:foundLine == -1
        let l:lineno = search(l:filename, 'W')
        if l:lineno != 0
            let l:tmpFilename = Project_GetFname(line('.'))
            if l:tmpFilename == l:absoluteFilename
                let l:foundLine = l:lineno
            else
                let l:lineno += 1
            endif
        endif
    endwhile

    if l:foundLine == -1
        call setpos('.', l:save_cursor)
        exe l:save_buffer.'wincmd w'
    else
        call feedkeys('zv')
    endif
endfunction; "}}} body }}}

"{{{ project pom/dependency dict
function! MvnGetPrjPomDict(projectHomePath, prjIdPomDict, refresh) "{{{
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
    if type(a:prjIdPomDict) != type({})
        throw "MvnGetPrjPomDict a:prjIdPomDict not a dict"
    endif
    if has_key(l:prjPomDict, 'created') && a:refresh == 0
        if l:prjPomDict['created'] > getftime(a:projectHomePath.'/pom.xml')
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
    else
        if !has_key(a:prjIdPomDict, l:prjPomDict.id)
            let a:prjIdPomDict[l:prjPomDict.id] = l:prjPomDict
        endif
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
            if type(eval(l:lineList[0])) == type({})
                let l:prjIdPomDict = eval(l:lineList[0])
            endif
        endif
    endif
    return l:prjIdPomDict
endfunction; "}}}

function! MvnSetPrjIdPomDict(filename, prjIdPomDict) "{{{
"Write out the master project dict to disk.
"a:prjIdPomDict - Dict store for all projects in the tree.
"   key: groupId:artifactId:version - project unique identifier.
"   value: a dict containing individual pom data ie prjPomDict
"       see MvnCreatePomDict().
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
"return - currentPomIndex
    let l:pomFile = a:pomList[a:currentPom]
    let l:projectPath = substitute(l:pomFile, "/pom.xml", "", "g")
    let l:projectName = matchstr(l:projectPath, "[^/]\\+.$")
    let l:allExtList = extend(extend([], a:srcExtList), a:resrcExtList)
    let l:prjPomDict = MvnGetPrjPomDict(l:projectPath, a:prjIdPomDict, 0)

    call insert(a:prjTreeTxt, repeat(' ', a:indentCount).l:projectName."="
        \  .l:projectPath." CD=. in=in.vim filter=\"".a:fileFilter."\" {", a:prjIndx)

    if a:prjIndx < 0
        call insert(a:prjTreeTxt, repeat(' ', a:indentCount)."}", a:prjIndx)
    else
        call add(a:prjTreeTxt, repeat(' ', a:indentCount)."}")
    endif

    "src main package dirs.
    call MvnBuildTopLevelDirEntries("srcMain", l:projectPath, l:prjPomDict,
        \ a:prjTreeTxt, a:prjIndx - 1, a:srcExtList, a:indentCount)
    call MvnBuildTopLevelDirEntries("webapp", l:projectPath, l:prjPomDict,
        \ a:prjTreeTxt, a:prjIndx - 1, l:allExtList, a:indentCount)
    "src test package dirs.
    call MvnBuildTopLevelDirEntries("srcTest", l:projectPath, l:prjPomDict,
        \ a:prjTreeTxt, a:prjIndx - 1, a:srcExtList, a:indentCount)
    "resource dirs.
    call MvnBuildTopLevelDirEntries("resrcMain", l:projectPath, l:prjPomDict,
        \ a:prjTreeTxt, a:prjIndx - 1, a:resrcExtList, a:indentCount)
    call MvnBuildTopLevelDirEntries("resrcTest", l:projectPath, l:prjPomDict,
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
function! MvnBuildTopLevelDirEntries(dirName, mvnProjectPath, prjPomDict,
    \masterProjectEntry, masterProjectIndx, javaSrcExtList, indentCount)
"Construct the directories for a maven project. Called once for each of:
"   src/main/java, src/main/resources, src/main/webapp, src/test/java,
"   src/test/resources
    if has_key(a:prjPomDict, a:dirName)
        if type(a:prjPomDict[a:dirName]) == type([])
            "TODO - We only take the first dir from the list, the workaround is to
            " create the tree entry manually. Must look at auto create of all dirs in the list.
            let l:subdirPath = a:prjPomDict[a:dirName][0]
        else
            let l:subdirPath = a:prjPomDict[a:dirName]
        endif
        let l:relPos = matchend(l:subdirPath, a:mvnProjectPath)
        if l:relPos == 0
            throw "MvnBuildTopeLevelDireEntries error. Project path == subdir path"
        elseif l:relPos == -1
            let l:relativePath = l:subdirPath
        else
            let l:relativePath = strpart(l:subdirPath,l:relPos+1)
        endif
        if isdirectory(a:mvnProjectPath."/".l:relativePath)
            let l:dirEntry = MvnBuildDirEntry(a:dirName, l:relativePath, a:indentCount + 1)
            let l:mainPackageList = MvnBuildDirList(a:mvnProjectPath, "/".l:relativePath."/", a:javaSrcExtList)
            let l:mainPackageEntries = MvnBuildSiblingDirEntries(l:mainPackageList, a:indentCount + 2)
            call extend(l:dirEntry, l:mainPackageEntries, -1)
            call extend(a:masterProjectEntry, l:dirEntry, a:masterProjectIndx)
        endif
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
function! MvnGetPrjIdPomFilename(checkCurrentBuffer) "{{{
"Check the current window is the project window.
"{{{ body
    if !exists('g:proj_running')
        throw "Is project running? Activate with ':Project'."
    endif
    if a:checkCurrentBuffer == 1 && bufnr('%') != g:proj_running
        throw "Please select the project window."
    endif
    let l:prjIdPomFilename= bufname(g:proj_running)."-mvn-ide"
    return  l:prjIdPomFilename
endfunction; "}}} body }}}
"}}} project utils

"{{{ xml pom functions
function! MvnGetPomFileData(projectHomePath) "{{{
"run maven to collect classpath and effective pom data as a string.
"{{{ body
    let l:mvnData = system("cd ".a:projectHomePath."; ".s:mvnCmd)
    return l:mvnData
endfunction; "}}} body }}}

function! MvnCreatePomDict(mvnData, projectHome, prjPomDict) "{{{
"Extract all required config from the pom data and cache in the dict.
"a:mvnData the text from a maven invocation, see MvnGetPomFileData().
"a:projectHome the directory containing pom.xml.
"a:prjPomDict a dict containing defaults read from in.vim.
"   keys: id, created, home, classpath, dependencies, srcMain, srcTest,
"   classMain, classTest, resrcMain, resrcTest.
"Return prjPomDict.
"{{{ body
    let l:pomDict = a:prjPomDict
    let l:pomDict['created'] = localtime()
    let l:pomDict['home'] = a:projectHome
    let l:classpath = MvnBuildRunClassPath(a:mvnData)
    let l:pomDict = MvnUpdateDict(l:pomDict, 'classpath', l:classpath)

    let l:effectivePom = a:mvnData
    let l:effectivePom = MvnTrimStringPre(l:effectivePom, "<project ")
    let l:effectivePom = MvnTrimStringPost(l:effectivePom, "</project>")
    if len(l:effectivePom) == 0
        throw "Maven command failed for project ".a:projectHome. " command: ".
        \s:mvnCmd
    endif
    let l:effectivePom = substitute(l:effectivePom, "\n", "", "g")
    let l:pomFilename = s:mvn_tmpdir."/effective-pom.xml"
    call writefile([l:effectivePom], l:pomFilename)
    "project pom id query
    let l:pomDict['id'] = MvnGetPomId(l:pomFilename)
    "dependency query
    let l:query = "/project/dependencies/*"
    let l:rawNodeList = MvnGetXPath(l:pomFilename, l:query)
    let l:nodeList = MvnParseNodesToList(l:rawNodeList)
    let l:dependencyIdList = MvnGetDependencyIdList(l:nodeList)

    let l:pomDict = MvnUpdateDict(l:pomDict, 'dependencies', l:dependencyIdList)
    "source main query
    let l:warningList = []
    call MvnAddElementToPomDict(l:pomDict, l:warningList, 'srcMain',
            \"/project/build/sourceDirectory/text\(\)", l:pomFilename)
    "source test query
    call MvnAddElementToPomDict(l:pomDict, l:warningList, 'srcTest',
            \"/project/build/testSourceDirectory/text\(\)", l:pomFilename)
    "main class query
    call MvnAddElementToPomDict(l:pomDict, l:warningList, 'classMain',
            \"/project/build/outputDirectory/text\(\)", l:pomFilename)
    "class test query
    call MvnAddElementToPomDict(l:pomDict, l:warningList, 'classTest',
            \"/project/build/testOutputDirectory/text\(\)", l:pomFilename)
    "resource main query
    call MvnAddElementToPomDict(l:pomDict, l:warningList, 'resrcMain',
        \"/project/build/resources/resource/directory/text\(\)", l:pomFilename)
    "resource test query
    call MvnAddElementToPomDict(l:pomDict, l:warningList, 'resrcTest',
        \"/project/build/testResources/testResource/directory/text\(\)",
        \l:pomFilename)
    call delete(s:mvn_tmpdir."/effective-pom.xml")
    let l:pomDict = MvnDefaultDictConfigurables(l:pomDict)
    if len(l:warningList) > 0
        echo join(l:warningList, ' ')
    endif
    return l:pomDict
endfunction; "}}} body }}}

"{{{ MvnAddElementToPomDict
function! MvnAddElementToPomDict(pomDict, warnList,
        \key, xquery, pomFilename )
"Update the project dict with the key and value.
"Add a warning message for keys with no value.
    let l:tmpPathList =  MvnGetStringsFromXPath(a:pomFilename, a:xquery)
    if len(l:tmpPathList) > 0
        let l:pomDict = MvnUpdateDict(a:pomDict, a:key, l:tmpPathList)
    else
        call add(a:warnList, a:pomDict['home'].' contains no key of '.a:key.'.')
    endif
endfunction; "}}} MvnAddElementToPomDict

function! MvnUpdateDict(pomDict, key, value) "{{{ 2
"Only add/update the key if the value is non zero. Else remove the key.
    if len(a:value) > 0
        let a:pomDict[a:key] = a:value
    else
        if has_key(a:pomDict, a:key)
            call remove(a:pomDict, a:key)
        endif
    endif
    return a:pomDict
endfunction; "}}} 2

function! MvnDefaultDictConfigurables(pomDict) "{{{ 2
    if !has_key(a:pomDict, 'webapp')
        let a:pomDict.webapp = s:mvn_projectMainWebapp
    endif
    return a:pomDict
endfunction; "}}} 2

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
"Return a string list containing the query data.
" or an empty list.
"{{{ 3
    let l:rawNodeList = MvnGetXPath(a:xmlFile, a:query)
    let l:nodeList = MvnParseNodesToList(l:rawNodeList)
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
    let l:prjIdPomFilename = MvnGetPrjIdPomFilename(1)
    let l:prjIdPomDict = MvnGetPrjIdPomDict(l:prjIdPomFilename)
    let l:dirList = MvnGetProjectDirList("", 0)
    for dir in l:dirList
        try
            echo printf("%s", "Refresh ".dir."/in.vim")
            let l:startTime = localtime()
            call MvnGetPrjPomDict(dir, l:prjIdPomDict, 1)
            echon printf(" %d sec", localtime() - l:startTime)
        catch /.*/
            echo "MvnRefresPrjIdPomDict error processing ".
                \dir." ".v:exception." ".v:throwpoint
        endtry
    endfor
    "TODO cycle through l:prjIdPomDict and remove non existant projects.
    call MvnSetPrjIdPomDict(l:prjIdPomFilename, l:prjIdPomDict)
endfunction; "}}} body }}}

function! MvnCreateEnvSelection() "{{{
"Build the environment for the consecutive project entries.
"{{{ body
    let l:prjIdPomFilename = MvnGetPrjIdPomFilename(1)
    let l:dirList = MvnGetProjectDirList("", 0)
    let l:prjIdPomDict = MvnGetPrjIdPomDict(l:prjIdPomFilename)
    "echo("Calculate the jdk runtime library using java -verbose -h.")
    let l:jreLib = MvnGetJreRuntimeLib()
    for dir in l:dirList
        try
            call MvnCreateEnv(dir, l:prjIdPomDict, l:jreLib)
        catch /No classpath/
            echo "MvnCreateEnv - ".l:dir." No classpath."
        catch /.*/
            echo "MvnCreateEnvSelection error processing".
                \dir." ".v:exception." ".v:throwpoint
        endtry
    endfor
    call MvnSetPrjIdPomDict(l:prjIdPomFilename, l:prjIdPomDict)
endfunction; "}}} body }}}

function! MvnCreateEnv(projectHomePath, prjIdPomDict, jreLib) "{{{
"Build the project in.vim sourced on access to a file in the project.
"Environment generated: g:vjde_lib_path, g:mvn_javadocPath,
"    g:mvn_javaSourcePath, g:mvn_currentPrjDict, path, tags.
"The environment paths are from 'mvn dependency:build-classpath' stored in
"prjPomDict['classpath'] and from the local project dependencies prepended to
"the paths.
"a:prjIdPomDict (see MvnSetPrjIdPomDict()).
"return prjIdPomDict - updated.
"{{{ body
    let l:startTime = localtime()
    let l:projectHomePath = a:projectHomePath
    if strlen(l:projectHomePath) == 0
        let l:projectHomePath = MvnGetProjectHomeDir()
        if !filereadable(a:projectHomePath."/pom.xml")
            echo("No project file :".a:projectHomePath."/pom.xml")
            return
        endif
    endif

    let l:prjPomDict = MvnGetPrjPomDict(l:projectHomePath, a:prjIdPomDict, 0)

    "Get the maven local sibling dependencies for a project to add to the path instead of jars.
    let l:siblingProjectIdList = MvnGetLocalDependenciesList(l:prjPomDict, a:prjIdPomDict)
    let l:projectIdList = insert(l:siblingProjectIdList, l:prjPomDict['id'])

    "Create the runtime classpath for the maven project.
    "echo("Calculate the runtime classpath using mvn dependency:build-classpath.") 21sec
    if !has_key(l:prjPomDict, 'classpath')
        throw "No classpath."
    else
        let l:mvnClassPath = l:prjPomDict['classpath']
        if strlen(l:mvnClassPath) == 0
            throw "No classpath."
        endif
    endif

    "Get the classMain dir for all other projects in vim Project.
    let l:projectRuntimeDirs = MvnGetPathsFromPrjDict(a:prjIdPomDict, l:projectIdList, 'classMain')
    "Add l:projectRuntimeDirs (target/classes) to the path ahead of l:mvnClassPath (the jars).
    let l:newline = "let g:vjde_lib_path=\"".l:projectRuntimeDirs.":".a:jreLib.":".l:mvnClassPath."\""
    call MvnUpdateFile(l:projectHomePath."/in.vim", "vjde_lib_path", l:newline)

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
    call MvnUpdateFile(l:projectHomePath."/in.vim", "mvn_javaSourcePath", l:newline)

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
    call MvnUpdateFile(l:projectHomePath."/in.vim", "mvn_javadocPath", l:newline)

    "set path
    let l:path = MvnConvertToPath(l:allJavaSourcePath)
    let l:newline = "let &path=\"".l:path."\""
    call MvnUpdateFile(l:projectHomePath."/in.vim", "let &path=", l:newline)

    "echo("Build tag files for all available source files.")
    let l:tagPath =  MvnBuildTags(l:prjPomDict['id'], l:javaSourcePath, l:projectIdList, a:prjIdPomDict)
    let l:newline = "let &tags=\"".l:tagPath."\""
    call MvnUpdateFile(l:projectHomePath."/in.vim", "let &tags=", l:newline)
    "echo "MvnCreateEnv Complete - ".l:projectHomePath." ".eval(localtime() - l:startTime)."s"
    return a:prjIdPomDict
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

function! MvnGetLocalDependenciesList(prjPomDict, prjIdPomDict) "{{{
"Return a list of maven ids of the local sibling projects depended on by
"this project if they exist. Remove dependency projects from prjIdPomDict if
"they no longer exist.
"Note parent projects may not contain dependencies in the effective-pom.
"a:prjPomDict - may contain a key to the project dependencies.
"a:prjIdPomDict - the dict of all sibling projects.
    let l:localDependencyIdList = []
    if has_key(a:prjPomDict, 'dependencies')
        "list of ids of the form groupId:artifactId:version.
        let l:dependencyIdList = a:prjPomDict['dependencies']
        for dependencyId in l:dependencyIdList
            if has_key(a:prjIdPomDict, dependencyId)
                let l:prjPomDict = a:prjIdPomDict[dependencyId]
                if isdirectory(l:prjPomDict['home'])
                    call add(l:localDependencyIdList, dependencyId)
                else
                    call remove(l:prjIdPomDict, dependencyId)
                endif
            endif
        endfor
    endif
    return l:localDependencyIdList
endfunction; "}}}

function! MvnGetPathsFromPrjDict(prjIdPomDict, idList, attribute) "{{{
"Return a path by appending path a:attribute from a:prjIdPomDict for each
"project in a:idList.
"a:prjIdPomDict - project configuration store, see MvnSetPrjIdPomDict().
"a:idList - the list of project identifiers of form groupId:artifactId:varsion.
"a:attribute - ie 'srcMain'
"{{{ body
    let l:dirs = []
    try
        for id in a:idList
            if has_key(a:prjIdPomDict[id], a:attribute)
                let l:dirList = a:prjIdPomDict[id][a:attribute]
                if len(l:dirList) > 0
                    let l:first = 1
                    for dir in l:dirList
                        call add(l:dirs, l:dir)
                    endfor
                endif
            endif
        endfor
    catch /.*/
        throw "id=".string(id)." idList=".string(a:idList)." ".v:exception." ".v:throwpoint
    endtry
    let l:dirPath = join(l:dirs, ":")
    return l:dirPath
endfunction; "}}} body }}}

function! MvnPomFileOrdering(pomFileList) "{{{
    let l:directoryList = []
    for l:pom in a:pomFileList
        let l:dir = substitute(l:pom, '/pom.xml$', '', 'g')
        call add(l:directoryList, l:dir)
    endfor
    let l:parentChildLists = MvnDirectoryParentChildSplit(l:directoryList)
    let l:reverseParentList = reverse(l:parentChildLists[0])
    let l:childList = l:parentChildLists[1]
    while len(l:childList) > 0
        let l:indx = 0
        let l:childPos = -1
        for l:parent in l:reverseParentList
            if l:childList[0] =~ '^'.l:parent
                let l:childPos = l:indx
                break
            endif
            let l:indx += 1
        endfor
        if l:childPos > -1
            call insert(l:reverseParentList, l:childList[0], l:childPos)
        endif
        call remove(l:childList, 0)
    endwhile
    let orderedPomList = []
    for l:dir in reverse(l:reverseParentList)
       call add(orderedPomList, l:dir.'/pom.xml')
    endfor
    return orderedPomList
endfunction; "}}}

function! MvnDirectoryParentChildSplit(directoryList) "{{{
"Return 2 lists in a list. ie [ parentList, childList ]
    let l:lengthSorted = sort(a:directoryList, function("MvnDirectorySort"))
    let l:parentList = []
    let l:childList = []
    for l:targetDir in l:lengthSorted
        let l:child = 0
        for l:testDir in l:lengthSorted
            if l:testDir != l:targetDir
                if l:targetDir =~ '^'.l:testDir
                   let l:child = 1
                   break
                endif
            endif
        endfor
        if l:child == 1
            call add(l:childList, l:targetDir)
        else
            call add(l:parentList, l:targetDir)
        endif
    endfor
    return [l:parentList, l:childList]
endfunction; "}}}

function! MvnDirectorySort(dir1, dir2) "{{{
"sort() Funcref to sort directories and their children in the required order
"for the project tree build. ie Parent directories must be ordered before
"their children. Sort short paths first, then when the path segment count
"is equal, sort reverse alphabetical. (Reverse alpha so after
"MvnPomFileOrdering the order is alpabetical.)
"return - 0 when equal,
"         1 if dir1 sorts after dir2,
"         -1 if dir1 sorts before dir2.
    "Compare the number of '/'
     let l:dirCount1 = len(a:dir1) - len(substitute(a:dir1, '/', '', 'g'))
     let l:dirCount2 = len(a:dir2) - len(substitute(a:dir2, '/', '', 'g'))
     if l:dirCount1 > l:dirCount2
         return 1
     elseif l:dirCount1 < l:dirCount2
         return -1
     endif

    "alphabetical sort
    let l:lenDir1 = len(a:dir1)
    let l:lenDir2 = len(a:dir2)
    if l:lenDir1 < l:lenDir2
        let l:lenDir = l:lenDir1
        let l:ret = 1
    else
        let l:lenDir = l:lenDir2
        let l:ret = -1
    endif
    let l:indx = 0
    while (l:indx < l:lenDir)
        if len(a:dir1) > l:indx
            if strpart(a:dir1, l:indx, 1) > strpart(a:dir2, l:indx, 1)
                return -1
            elseif strpart(a:dir1, l:indx, 1) < strpart(a:dir2, l:indx, 1)
                return 1
            endif
        else
            return l:ret
        endif
        let l:indx += 1
    endwhile
    "This sort crashes vim?? replaced by alphabetical sort above.
    "let l:tmpSorted = sort([a:dir1, a:dir2])
    "if l:tmpSorted[0] == a:dir1
    "    return -1
    "endif
    return l:ret
endfunction; "}}}

function! MvnGetProjectHomeDir() "{{{
"return - the absolute path for the project ie where the pom.xml is.
    let l:projTargetClassesPath = matchstr(system('pwd'), "\\p\\+")
    return l:projTargetClassesPath
endfunction; "}}}

function! MvnGetJreRuntimeLib() "{{{
    let l:javaOP = system("java -verbose |grep Opened")
    let l:jreLib = matchstr(l:javaOP, "Opened \\p\\+")
    let l:jreLib = matchstr(l:jreLib, "/.\\+jar")
    return l:jreLib
endfunction; "}}}

function! MvnBuildRunClassPath(mvnData) "{{{
"Create the classpath from the maven project.
"return - the maven classpath
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
"  does not exist in the file then add it. The MvnSetEnv call must be on
"  the last line.
    if filereadable(a:filename)
        let l:lines = readfile(a:filename)
        let l:lineNo = match(l:lines, 'MvnSetEnv')
        if l:lineNo == -1
            call add(l:lines,'call MvnSetEnv()')
        elseif l:lineNo != (len(l:lines) - 1)
            call add(l:lines, remove(l:lines, l:lineNo))
        endif
    else
        let l:lines = ['call MvnSetEnv()']
    endif
    let l:lineNo = match(l:lines, a:id)
    if l:lineNo >= 0
        "The entry exists so remove it and add it back in the same position.
        call remove(l:lines, l:lineNo)
        call insert(l:lines, a:newline, l:lineNo)
    else
        "Does not exist so add it to the end of the file
        "before the function call.
        call insert(l:lines, a:newline, len(l:lines)-1)
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

function! MvnGetInVimSetting(filename, setting) "{{{
    let l:lines = readfile(a:filename)
    let l:lineNo = match(l:lines, a:setting)
    let l:settingLine = l:lines[l:lineNo]
    let l:pos = matchend(l:settingLine, '=')
    let l:setting = strpart(l:settingLine, l:pos)
    return l:setting
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
function! s:MvnPlugin.getType()
    throw "No plugin type set."
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
" For maven2 compiler 2.5
   let this = copy(self)
   let super = s:MvnPlugin.New()
   call extend(this, deepcopy(super), "keep")
   call this.addStartRegExp('^\[ERROR\] BUILD FAILURE')
   call this.addStartRegExp('^\[INFO\] -\+')
   call this.addStartRegExp('^\[INFO\] Compilation failure')
   return this
endfunction
function! s:Mvn2Plugin.getType()
    return 'compiler'
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
                    "blank line
                elseif match(l:line, 'location: ') == 0 ||
                    \match(l:line, 'symbol  : ') == 0
                    let l:pos = len(l:quickfixList)
                    if l:pos > 0
                        let l:fixDict = l:quickfixList[l:pos - 1]
                        if has_key(l:fixDict, 'text')
                            let l:errorMsg = l:fixDict['text'].' '. l:line
                            let l:fixDict['text'] = l:errorMsg
                        else
                            echo 'Parse error: no quickfix text??'
                        endif
                    else
                        echo 'Parse error: empty quickfixList??'
                    endif
                else
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
                    let l:fixDict = {'bufnr': '', 'filename': l:filename,
                        \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                        \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}
                    call add(l:quickfixList, l:fixDict)
                endif
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
" For maven3 compiler 2.5
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^\[ERROR\] COMPILATION ERROR :')
    return this
endfunction
function! s:Mvn3Plugin.getType()
    return 'compiler'
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

                "Get the multi line error message.
                let messageCtr = l:lineNo
                let l:messageEnd = 0
                let l:message = strpart(l:line, l:posStart)
                while l:messageEnd == 0
                    let l:messageCtr += 1
                    if match(self._mvnOutputList[messageCtr], '^[') == -1
                        let l:message .= ' '.self._mvnOutputList[messageCtr]
                    else
                        let l:messageEnd = 1
                    endif
                endwhile

                let l:fixDict = {'bufnr': '', 'filename': l:filename,
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixDict)

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
endfunction
function! s:JunitPlugin.getType()
    return 'junit'
endfunction
function! s:JunitPlugin.processJunitOutput(outputData)
    "Process the output when the test class is run directly ie not under maven.
    "see getqflist()
    throw "Add maven-ide JunitPlugin processing code to the subclass."
endfunction
function! s:JunitPlugin.processJunitOutput(outputData) "{{{ processJunitOutput
    let l:quickfixList = []
    let l:ctr = 0
    let l:errorSize = len(a:outputData)
    while l:ctr != -1 && l:ctr < l:errorSize
        let l:ctr = match(a:outputData, '^\d\+)\s', l:ctr + 1)
        if l:ctr> -1
            "Found error start line.
            "Get the multi line error message.
            let messageCtr = l:ctr
            let l:messageEnd = 0
            let l:errorMessage = a:outputData[messageCtr]
            while l:messageEnd == 0
                let l:messageCtr += 1
                if match(a:outputData[messageCtr], '\s\+at\s\S') == -1
                    let l:errorMessage .= a:outputData[messageCtr]
                else
                    let l:messageEnd = 1
                endif
            endwhile
            "Get the name of the class in error.
            let l:line = a:outputData[l:ctr]
            let l:posStart = stridx(l:line, '(') + 1
            let l:posEnd = stridx(l:line, ')', l:posStart)
            let l:errorClass = strpart(l:line, l:posStart, l:posEnd - l:posStart)
            "Find the class in the stack trace.
            let l:ctr = match(a:outputData, l:errorClass, l:ctr + 1)
            if l:ctr == -1
                throw "Unable to parse Junit error error 3."
            endif
            let l:line = a:outputData[l:ctr]
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
            let l:qfixLine = {'bufnr': '', 'filename': l:absoluteFilename,
                \'lnum': l:errorLineNo, 'pattern': '', 'col': '',
                \'vcol': '', 'nr': '', 'text': l:errorMessage, 'type': 'E'}
            call add(l:quickfixList, l:qfixLine)
        endif
    endwhile
    call reverse(l:quickfixList)
    return l:quickfixList
endfunction "}}} processJunitOutput }}} junitPlugin

let s:Junit3Plugin = {} "{{{ junit3Plugin
function! s:Junit3Plugin.New()
" For version 3.8.2
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
        let l:testFinish += 1
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
            else
                let l:lineNo += 1
            endif
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:testFinish
            let l:ret.quickfixList = l:quickfixList
            call MvnEcho('Using maven-ide junit v'.self.getVersion().
                    \' plugin.')
        endif
    endif
    return l:ret
endfunction "}}} processErrors
function! s:Junit3Plugin.doFailure(lineNo, finishLineNo) "{{{ doFailure
    let l:lineNo = a:lineNo + 1
    "Get the multi line error message.
    let messageCtr = l:lineNo
    let l:messageEnd = 0
    let l:message = self._mvnOutputList[messageCtr]
    while l:messageEnd == 0
        let l:messageCtr += 1
        if match(self._mvnOutputList[messageCtr], '\s\+at\s\S') == -1
            let l:message .= self._mvnOutputList[messageCtr]
        else
            let l:messageEnd = 1
        endif
    endwhile

    "find the start of the next error or the end of errors (blank line).
    let l:endPosList = []
    call add(l:endPosList, match(self._mvnOutputList, '^$', l:lineNo))
    call add(l:endPosList, match(self._mvnOutputList, '<<< FAILURE!$', l:lineNo))
    call add(l:endPosList, match(self._mvnOutputList, '<<< ERROR!$', l:lineNo))
    let l:tmpList = reverse(sort(l:endPosList))
    let l:endPosList = l:tmpList
    if l:endPosList[0] == -1
        throw "Unable to parse Junit error 1."
    else
        let l:failFinishLine = l:endPosList[0]
    endif
    for l:endPos in l:endPosList
        if l:endPos != -1 && l:endPos < l:failFinishLine
            let l:failFinishLine = l:endPos
        endif
    endfor
    if l:failFinishLine > a:finishLineNo || l:failFinishLine == -1
        throw "Unable to parse Junit error 2."
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
    let l:revertTestEnv = 0
    if !g:mvn_isTest
        let l:revertTestEnv = 1
        let l:vjde_lib_path = g:vjde_lib_path
        let l:mvn_javaSourcePath = g:mvn_javaSourcePath
        let l:oldpath = &path
        let l:oldtags = &tags
        call MvnDoSetTestEnv(g:mvn_currentPrjDict)
    endif
    let l:absoluteFilename = findfile(l:filename)
    if l:revertTestEnv == 1
        let g:vjde_lib_path = l:vjde_lib_path
        let g:mvn_javaSourcePath = l:mvn_javaSourcePath
        let &path = l:oldpath
        let &tags = l:oldtags
    endif
    if len(l:absoluteFilename) == 0
        echo 'Can not find '.l:filename
    endif
    let l:fixDict = {'bufnr': '', 'filename': l:absoluteFilename,
        \'lnum': l:errorLineNo, 'pattern': '', 'col': '',
       \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

    return {'lineNo': l:failFinishLine, 'fixList': l:fixDict }
endfunction  "}}} doFailure
function! s:Junit3Plugin.getVersion() "{{{ getVersion
    return 3
endfunction "}}} getVersion
function! s:Junit3Plugin.getRunClass() "{{{ getRunClass
    return "junit.textui.TestRunner"
endfunction "}}} getRunClass }}} junit3Plugin

let s:Junit4Plugin = {} "{{{ junit4Plugin
function! s:Junit4Plugin.New()
" For version 4.8
    let this= copy(self)
    let super = s:JunitPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^ T E S T S')
    call this.addStartRegExp('^-\+')
    return this
endfunction
function! s:Junit4Plugin.processErrors() "{{{ processErrors
"return dict { lineNumber, quickfixList }
"   quickfixList of dict : {bufnr, filename, lnum, pattern, col, vcol, nr, text, type}
    let l:ret = {'lineNumber': self._currentLine, 'quickfixList': []}
    let l:testFinish = match(self._mvnOutputList, '^Results :',
        \ self._currentLine + 1)
    if l:testFinish != -1
        let l:testFinish = match(self._mvnOutputList, '^Tests run:',
            \ l:testFinish)
        let l:testFinish += 1
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
            else
                let l:lineNo += 1
            endif
        endwhile
        if len(l:quickfixList) > 0
            let l:ret.lineNumber = l:testFinish
            let l:ret.quickfixList = l:quickfixList
            call MvnEcho('Using maven-ide junit v'.self.getVersion().
                    \' plugin.')
        endif
    endif
    return l:ret
endfunction "}}} processErrors
function! s:Junit4Plugin.doFailure(lineNo, finishLineNo) "{{{ doFailure
    let l:errorClassLine = self._mvnOutputList[a:lineNo]
    "the class name is in ().
    let l:posStart = stridx(l:errorClassLine, '(') + 1
    let l:posEnd = stridx(l:errorClassLine, ')')
    let l:errorClass = strpart(l:errorClassLine, l:posStart, l:posEnd - l:posStart)
    let l:lineNo = a:lineNo + 1
    "Get the multi line error message.
    let messageCtr = l:lineNo
    let l:messageEnd = 0
    let l:message = self._mvnOutputList[messageCtr]
    while l:messageEnd == 0
        let l:messageCtr += 1
        if match(self._mvnOutputList[messageCtr], '\s\+at\s\S') == -1
            let l:message .= self._mvnOutputList[messageCtr]
        else
            let l:messageEnd = 1
        endif
    endwhile

    "find the start of the next error or the end of errors (blank line).
    let l:endPosList = []
    call add(l:endPosList, match(self._mvnOutputList, '^$', l:lineNo))
    call add(l:endPosList, match(self._mvnOutputList, '<<< FAILURE!$', l:lineNo))
    call add(l:endPosList, match(self._mvnOutputList, '<<< ERROR!$', l:lineNo))
    let l:tmpList = reverse(sort(l:endPosList))
    let l:endPosList = l:tmpList
    if l:endPosList[0] == -1
        throw "Unable to parse Junit error 1."
    else
        let l:failFinishLine = l:endPosList[0]
    endif
    for l:endPos in l:endPosList
        if l:endPos != -1 && l:endPos < l:failFinishLine
            let l:failFinishLine = l:endPos
        endif
    endfor
    if l:failFinishLine > a:finishLineNo || l:failFinishLine == -1
        throw "Unable to parse Junit error 2."
    endif
    "find the class in the stack trace.
    let l:errorLine = match(self._mvnOutputList, l:errorClass, l:lineNo)
    if (l:errorLine > l:failFinishLine) || l:errorLine == -1
        throw "Unable to parse Junit error error 3."
    endif
    let l:line = self._mvnOutputList[l:errorLine]
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

    let l:filename = substitute(l:errorClass, '\.', '/', 'g')
    let l:filename .= '.java'
    let l:revertTestEnv = 0
    if !g:mvn_isTest
        let l:revertTestEnv = 1
        let l:vjde_lib_path = g:vjde_lib_path
        let l:mvn_javaSourcePath = g:mvn_javaSourcePath
        let l:oldpath = &path
        let l:oldtags = &tags
        call MvnDoSetTestEnv(g:mvn_currentPrjDict)
    endif
    let l:absoluteFilename = findfile(l:filename)
    if l:revertTestEnv == 1
        let g:vjde_lib_path = l:vjde_lib_path
        let g:mvn_javaSourcePath = l:mvn_javaSourcePath
        let &path = l:oldpath
        let &tags = l:oldtags
    endif
    if len(l:absoluteFilename) == 0
        echo 'Can not find '.l:filename
    endif
    let l:fixDict = {'bufnr': '', 'filename': l:absoluteFilename,
        \'lnum': l:errorLineNo, 'pattern': '', 'col': '',
       \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

    return {'lineNo': l:failFinishLine, 'fixList': l:fixDict }
endfunction "}}} doFailure
function! s:Junit4Plugin.getVersion() "{{{ getVersion
    return 4
endfunction "}}} getVersion
function! s:Junit4Plugin.getRunClass() "{{{ getRunClass
    return "org.junit.runner.JUnitCore"
endfunction "}}} getRunClass }}} junit4Plugin

let s:CheckStyle22Plugin = {} "{{{ checkStylePlugin
function! s:CheckStyle22Plugin.New()
"For maven plugin:
"  <groupId>org.apache.maven.plugins</groupId>
"  <artifactId>maven-checkstyle-plugin</artifactId>
"  <version>2.2</version>
    let this = copy(self)
    let super = s:MvnPlugin.New()
    call extend(this, deepcopy(super), "keep")
    call this.addStartRegExp('^\[INFO\] Starting audit...')
    return this
endfunction
function! s:CheckStyle22Plugin.getType()
    return 'checkstyle'
endfunction
function! s:CheckStyle22Plugin.processErrors() "{{{ processErrors
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

                let l:fixDict = {'bufnr': '', 'filename': l:filename,
                    \'lnum': l:errorLineNo, 'pattern': '', 'col': l:errorColNo,
                    \'vcol': '', 'nr': '', 'text': message, 'type': 'E'}

                call add(l:quickfixList, l:fixDict)

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

function! MvnPluginInit() "{{{
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
endfunction; "}}}

function! MvnGetJunitPlugin(classpath) "{{{
    let l:junitPlugin = MvnGetPlugin('junit')
    let l:pos = match(a:classpath, '[:/]junit-[0-9.]\+jar') + 7
    if l:pos != -1
        let l:version = strpart(a:classpath, l:pos, 1)
        try
            let l:junitPlugin = eval('s:Junit'.l:version.'Plugin').New()
        catch /.*/
            throw 'No junit plugin for version '.l:version.'.'
        endtry
    endif
    return l:junitPlugin
endfunction; "}}}

function! MvnGetPlugin(type) "{{{
    for plugin in s:plugins
        if plugin.getType() == a:type
            return plugin
        endif
    endfor
    throw "No plugin of type ".a:type
endfunction; "}}}
"}}} mavenOutputProcessorPlugins

function! MvnCompile() "{{{
"Full project compilation with maven.
"   Don't use standard quickfix functionality - maven output seems
"   challenging for vim builtin error formatting, so implement explicit
"   invocation of compile, processing of output messages and
"   build of quickfix list.
    call setqflist([])
    let l:outfile = s:mvn_tmpdir."/mvn.out"
    call system('mkdir -p '.s:mvn_tmpdir)
    call delete(l:outfile)
    "surefire.useFile=false - force junit output to the console.
    let l:cmd = "mvn ".s:mvn_offline." clean ".
    \"org.apache.maven.plugins:maven-compiler-plugin:".
    \g:mvn_compilerVersion.":compile install -Dsurefire.useFile=false"

    if strlen(v:servername) == 0
        let l:cmd = "!".l:cmd
        let l:cmd .=" | tee ".l:outfile
        exec l:cmd
        call MvnOP2QuickfixList(l:outfile)
    else
        let l:Fn = function("MvnOP2QuickfixList")
        let l:cmd .=" | tee ".l:outfile
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
    call MvnPluginOutputInit(s:plugins, '')
    return l:quickfixList
endfunction; "}}}

function! MvnJavacCompile() "{{{
"Allow for quick single file compilation with javac.

    "Is the source file in the project?
    let l:srcFile = expand('%:p')
    let l:prjPomDict = g:mvn_currentPrjDict
    call MvnIsTestSrc(l:srcFile, l:prjPomDict)

    let l:classpath = g:vjde_lib_path
    if g:mvn_isTest == 1
        let l:target = g:mvn_currentPrjDict['classTest'][0]
    else
        let l:target = g:mvn_currentPrjDict['classMain'][0]
    endif

    compiler javac_ex
    let &makeprg="javac  -g -d " . l:target . " -cp " . l:classpath . "  %"
    if strlen(v:servername) == 0
        make
    else
        "background execution of compile.
        call asynccommand#run(&makeprg, asynchandler#quickfix(&errorformat, ""))
    endif
endfunction; "}}}

function! MvnIsTestSrc(srcFile, prjPomDict) "{{{
    let l:isTest = 0
    if has_key(a:prjPomDict, 'srcTest')
        for l:testPath in a:prjPomDict['srcTest']
            if match(a:srcFile, l:testPath) == 0
                let isTest = 1
            endif
        endfor
    endif
    if isTest == 0 && has_key(a:prjPomDict, 'srcMain')
        let isMain = 0
        for l:mainPath in a:prjPomDict['srcMain']
            if match(a:srcFile, l:mainPath) == 0
                let isMain = 1
            endif
        endfor
        if isMain == 0 && bufnr('%') != g:proj_running
            if match(a:srcFile, a:prjPomDict['home']) != 0
                throw "Source file " . a:srcFile . " is not in the environment" .
                \"path for project " . a:prjPomDict['home']
            endif
        endif
    endif
    return l:isTest
endfunction; "}}}

function! MvnSetEnv(...) "{{{
"Invoked from the project in.vim scripts to set the environment
"for test source and debugging.  Setter of the g:mvn_isTest flag.
    if a:0 == 0
        let l:srcFile = expand('%:p')
        let l:ext = expand('%:e')
        let l:prjPomDict = g:mvn_currentPrjDict
    else
        "test case
        let l:srcFile = a:1
        let l:prjPomDict = a:2
        let l:ext = a:3
    endif
    if MvnIsTestSrc(srcFile, l:prjPomDict)
        call MvnDoSetTestEnv(l:prjPomDict)
        let g:mvn_isTest = 1
    else
        let g:mvn_isTest = 0
    endif
    if l:ext == "js"
        "run in projecthome ie:
        "jsctags `pwd`/src/main/webapp/script/ext-js -f tags-script
        "remove \r from the end of the lines
        ":%s/\\r$\/;/$\/;
        let l:jstags = g:mvn_currentPrjDict['home'].'/tags-script'
        if filereadable(l:jstags)
            let &tags = l:jstags
        endif
    endif
    if exists('*VDBIsConnected')
        if VDBIsConnected()
            let &path = g:mvn_debugpath
        endif
    endif
endfunction; "}}}

function! MvnDoSetTestEnv(prjPomDict) "{{{
        if has_key(a:prjPomDict, 'classTest')
            let g:vjde_lib_path = join(a:prjPomDict['classTest'], ':').
            \':'.g:vjde_lib_path
        endif
        if has_key(a:prjPomDict, 'srcTest')
            let g:mvn_javaSourcePath = join(a:prjPomDict['srcTest'], ':') .':'.
                \g:mvn_javaSourcePath
            let &path = join(a:prjPomDict['srcTest'], '/**,'). '/**,'. &path
            let l:tagfile = a:prjPomDict['home'] . '/tags-t'
            if filereadable(l:tagfile)
                let &tags = l:tagfile.','.&tags
            endif
        endif
endfunction; "}}}
"}}} Compiler -----------------------------------------------------------------

"{{{ Debugging ----------------------------------------------------------------
function! MvnDoDebug() "{{{
"Set the debug environment and run the debugger. Allow selection of the debug
"target from a list. The default target is the current file. g:mvn_debugPortList
"may be configured for additional debug targets.
"
"Set g:mvn_debugpath so the &path may be adjusted allowing stepping out of a
"source file in a low level dependency back to a source file at a higher
"dependency level.
"
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

"tomcat debug options:   -agentlib:jdwp=transport=dt_socket,server=y,address=11550,suspend=n
" jdb -sourcepath -attach 11550
"
    if strlen(v:servername) == 0
        echo "No servername!"
    else
        if !exists('*VDBIsConnected')
            echo "Patch not applied to yavdb."
        endif
        call s:TestExecutable('yavdb')

        "Is the source file in the project?
        let l:srcFile = expand('%:p')
        let l:prjPomDict = g:mvn_currentPrjDict
        call MvnIsTestSrc(l:srcFile, l:prjPomDict)

        let l:classPath =  g:vjde_lib_path
        let l:isTest = g:mvn_isTest

        "Prompt for the debug host/port number.
        let l:debugSelectionList = MvnGetDebugTargetList()
        call inputsave()
        let l:SelectedOption= inputlist(l:debugSelectionList)
        call inputrestore()

        if l:SelectedOption == -1 || l:SelectedOption > len(l:debugSelectionList)
            return
        endif

        let l:host = ''
        let l:tmpSourcePath = g:mvn_javaSourcePath
        if l:SelectedOption == 0
            let l:port = g:mvn_debugPortList[0]
            call MvnRunDebugProcess(l:port, l:classPath,
                \l:isTest, expand('%:p'), l:prjPomDict)
            let g:mvn_debugpath = &path
        else
            let l:portHostList = split(g:mvn_debugPortList[l:SelectedOption-1], ':')
            if len(l:portHostList) == 1
                let l:port = l:portHostList[0]
            elseif len(l:portHostList) == 2
                let l:port = l:portHostList[1]
                let l:host = l:portHostList[0]
            else
                throw "Invalid host:port ". join(l:portHostList, ":")
            endif
            if l:isTest == 1
                "Store the path for the current project.
                let g:mvn_debugpath = &path
            else
                "Who knows what parent source code we will need to step into from the
                "current file.  So build a list of parent project dependant on the
                "current file. Prompt for selection of the parent project.
                let l:prjIdPomFilename = MvnGetPrjIdPomFilename(0)
                let l:prjIdPomDict = MvnGetPrjIdPomDict(l:prjIdPomFilename)
                let l:projectSelectionList = MvnGetParentProjects(
                    \l:prjPomDict, l:prjIdPomDict)
                if len(l:projectSelectionList) > 0
                    let l:selectedId = MvnGetSelectedProject(l:projectSelectionList)
                    "TODO retrieve the in.vim filename via l:selectedId
                    let l:inVimFilename = l:prjIdPomDict[l:selectedId]['home'].
                        \'/in.vim'
                    let g:mvn_debugpath = MvnGetInVimSetting(l:inVimFilename, "&path")
                    let l:tmpSourcePath = MvnGetInVimSetting(l:inVimFilename, "mvn_javaSourcePath")
                else
                    let g:mvn_debugpath = &path
                endif
            endif
        endif

        "Execute the debugger.
        let l:debugger = "!xterm -T yavdb -e ".s:mvn_scriptDir."/bin/yavdb.sh "
        let l:debugger .= v:servername . " " . l:tmpSourcePath ." ".l:port." ".l:host
        let l:debugger.= " |tee ".s:mvn_tmpdir."/dbgjdb.out &"
        exec l:debugger
    endif
endfunction; "}}}

function! MvnGetDebugTargetList() "{{{
    let l:debugSelectionList=[]
    let l:firstOption = "0: Run and debug current file port:"
    let l:firstOption .= g:mvn_debugPortList[0]
    call add(l:debugSelectionList, l:firstOption)

    let l:count = 1
    for l:hostPort in g:mvn_debugPortList
        call add(l:debugSelectionList, l:count . ") connect to " . l:hostPort .".")
        let l:count += 1
    endfor
    return l:debugSelectionList
endfunction; "}}}

function! MvnGetSelectedProject(projectSelectionList) "{{{
"Prompt with the list for a selection.
"Return the project id selected.
    if len(a:projectSelectionList) > 1
        call inputsave()
        redraw
        let l:selectedOption = inputlist(a:projectSelectionList)
        call inputrestore()
        if l:selectedOption > len(a:projectSelectionList) ||
            \l:selectedOption < 0
            let l:selectedOption = 1
        endif
    else
        let l:selectedOption = 1
    endif
    let l:selection = a:projectSelectionList[l:selectedOption-1]
    let l:pos = stridx(l:selection, ':')
    let l:pos = stridx(l:selection, ':', l:pos + 1)
    let l:selectedId = strpart(l:selection, l:pos + 1)
    return l:selectedId
endfunction; "}}}

function! MvnGetParentProjects(prjPomDict, prjIdPomDict) "{{{
"Find the projects depending on the project containing the current file.
"   keys: id, created, home, classpath, dependencies, srcMain, srcTest,
"   classMain, classTest, resrcMain, resrcTest.
    let l:currentId= a:prjPomDict['id']
    let l:prjIdList = []
    let l:prjDirList = []
    "Build a list of id's dependant on the project.
    for l:tmpPrjDict in values(a:prjIdPomDict)
        if has_key(l:tmpPrjDict, 'dependencies')
            let l:tmpDependencyList = l:tmpPrjDict['dependencies']
            for l:prjId in l:tmpDependencyList
                if l:prjId == l:currentId
                   call add(l:prjIdList, l:tmpPrjDict['id'])
                endif
            endfor
        endif
    endfor
    "From the id list build a list of project paths.
    let l:pathIdList = []
    let l:count = 1
    for l:prjId in l:prjIdList
       call add(l:pathIdList, l:count.':'.a:prjIdPomDict[l:prjId]['home'].':'.l:prjId)
       let l:count += 1
    endfor
    return l:pathIdList
endfunction; "}}}

function! MvnRunDebugProcess(port, classpath, isTest, filename, prjPomDict) "{{{
"run the java program or unit test.
    let l:classUnderDebug = MvnGetClassFromFilename(a:filename, a:prjPomDict)
    "Execute the java class or test runner.
    let l:javaProg = "!xterm  -T ".l:classUnderDebug
    let l:javaProg .= " -e ".s:mvn_scriptDir."/bin/run.sh "
    let l:javaProg .= " \"java -Xdebug -Xrunjdwp:transport=dt_socket"
    let l:javaProg .= ",address=".a:port.",server=y,suspend=y"
    if a:isTest
        let l:junitPlugin = MvnGetJunitPlugin(a:classpath)
        let l:javaProg .= MvnGetJunitCmdString(a:classpath, l:classUnderDebug,
            \l:junitPlugin)
    else
        let l:javaProg .= " -classpath ".a:classpath
        let l:javaProg .= " ".l:classUnderDebug
    endif
    let l:javaProg .= "\" &"
    exec l:javaProg
endfunction; "}}}

function! MvnGetClassFromFilename(absoluteFilename, prjPomDict) "{{{
"From the absolute java source file name determine the package class name.
    let l:srcFile = a:absoluteFilename
    let l:pos = -1
    if has_key(a:prjPomDict, 'srcTest')
        for l:testPath in a:prjPomDict['srcTest']
            if match(l:srcFile, l:testPath) == 0
                let l:pos = matchend(l:srcFile, l:testPath)
            endif
        endfor
    endif
    if l:pos == -1 && has_key(a:prjPomDict, 'srcMain')
        for l:mainPath in a:prjPomDict['srcMain']
            if match(l:srcFile, l:mainPath) == 0
                let l:pos = matchend(l:srcFile, l:mainPath)
            endif
        endfor
        if l:pos == -1
            if match(l:srcFile, a:prjPomDict['home']) != 0
                throw "Source file " . l:srcFile . " is not in the environment" .
                \"path for project " . a:prjPomDict['home']
            endif
        endif
    endif

    let l:pos += 1
    let l:className = strpart(l:srcFile, l:pos)
    let l:pos = match(l:className, '.java$')
    if l:pos == -1
        throw "Error - No class for ".l:srcFile
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

"{{{ MvnInstallJavadocFromSource
function! MvnInstallJavadocFromSource(javadocParentDir, javaSourceParentDir,
        \unavailableJavadoc, unavailableSource)
"If the source exists build and install the javadoc.
"a:javadocParentDir - the installation directory for javadoc.
"a:javaSourceParentDir - the installation directory for source.
"a:unavailableJavadoc - unavailable javadoc jar list.
"a:unavailableSource - unavailable source jar list.
"{{{ body
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
endfunction; "}}} body }}} MvnInstallJavadocFromSource

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

function! MvnFindSubclass(superclass) "{{{
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
"Show the list of subclasses from the MvnFindSubclass search.
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
    let l:tagFilename = ''
    if has_key(a:prjPomDict, 'home') && has_key(a:prjPomDict, 'srcMain')
        let l:homeDir = a:prjPomDict['home']
        let l:srcDirList = a:prjPomDict['srcMain']
        let l:isChild = MvnFileIsChild(l:srcDirList, a:srcPath)
        if l:isChild == 1
            let l:tagFilename = l:homeDir . "/tags"
        endif
        "no srcMain so check srcTest
        if has_key(a:prjPomDict, 'srcTest') && l:tagFilename == ''
            let l:srcDirList = a:prjPomDict['srcTest']
            let l:isChild = MvnFileIsChild(l:srcDirList, a:srcPath)
            if l:isChild == 1
                let l:tagFilename = l:homeDir . "/tags-t"
            endif
        endif
    endif
    "when no match put the tag file next to the source file.
    if len(l:tagFilename) == 0
        let l:tagFilename = a:srcPath.'/tags'
    endif
    return l:tagFilename
endfunction; "}}} body }}}

function! MvnFileIsChild(dirList, fileDir) "{{{
"Is the fileDir in the tree of one of the directories in the list.
    let l:found = 0
    let l:indx = 0
    while l:indx < len(a:dirList) && l:found == 0
        let l:dir = a:dirList[l:indx]
        let l:pos = matchend(a:fileDir, l:dir)
        if l:pos == len(l:dir)
            let l:found = 1
        endif
        let l:indx += 1
    endwhile
    return l:found
endfunction; "}}}

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
        let l:srcDirList = a:prjIdPomDict[prjId]['srcMain']
        for l:srcDir in l:srcDirList
            let l:tagfile = a:prjIdPomDict[prjId]['home'].'/tags'
            if prjId == a:currentPrjId
                call MvnCreateTagFile(l:tagfile, l:srcDir)
            endif
        endfor
        if strlen(l:tagPath) > 0
            let l:tagPath .= ","
        endif
        let l:tagPath .= l:tagfile
    endfor
    if len(a:currentPrjId) > 0
        "Initial tag path does not include test tag file.
        let prjId = a:currentPrjId
        let l:srcDirList = a:prjIdPomDict[a:currentPrjId]['srcTest']
        for l:srcDir in l:srcDirList
            let l:tagfile = a:prjIdPomDict[a:currentPrjId]['home'].'/tags-t'
            call MvnCreateTagFile(l:tagfile, l:srcDir)
        endfor
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

"{{{ Misc ---------------------------------------------------------------------
function! MvnEcho(message)
"Does not echo message when running the unit tests.
    if s:mvn_inUnitTest == 0
        echo a:message
    endif
endfunction;

function! MvnGetJunitCmdString(classpath, classUnderDebug, junitPlugin)
    let l:junitRunClass = a:junitPlugin.getRunClass()
    let l:junitCmd = " -classpath ".a:classpath." ".l:junitRunClass." ".a:classUnderDebug
    return l:junitCmd
endfunction;

function! MvnShowMavenOutput()
    exec "!less ".s:mvn_tmpdir."/mvn.out"
endfunction;

function! MvnRunJunit() "{{{
"Run test add errors to quickfix list.
"{{{ body
    "Is the source file in the project?
    let l:srcFile = expand('%:p')
    let l:prjPomDict = g:mvn_currentPrjDict
    call MvnIsTestSrc(l:srcFile, l:prjPomDict)

    let l:classpath = g:vjde_lib_path
    let l:testClass = MvnGetClassFromFilename(expand('%:p'), g:mvn_currentPrjDict)
    if strlen(l:testClass) == 0
        return -1
    endif
    let l:junitPlugin = MvnGetJunitPlugin(l:classpath)
    let l:cmd = MvnGetJunitCmdString(l:classpath, l:testClass, l:junitPlugin)
    let l:cmd = "!java ". l:cmd
    let l:cmd = l:cmd." | tee ".s:mvn_tmpdir."/junit.out"
    exec l:cmd
    let l:testOutput = readfile(s:mvn_tmpdir."/junit.out")
    let l:quickfixList = l:junitPlugin.processJunitOutput(l:testOutput)

    if len(l:quickfixList) > 0
        call setqflist(l:quickfixList)
        cl
    endif
endfunction; "}}} body }}}
"}}} Misc ---------------------------------------------------------------------

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
    let l:junitPlugin = MvnGetJunitPlugin('abc.jar:junit-4.8.jar')
    let l:version = l:junitPlugin.getVersion()
    call a:testR.AssertEquals('Test MvnGetJunitPlugin', 4, l:junitPlugin.getVersion())
    let l:junitPlugin = MvnGetJunitPlugin('abc.jar:junit-3.8.jar')
    let l:version = l:junitPlugin.getVersion()
    call a:testR.AssertEquals('Test MvnGetJunitPlugin', 3, l:junitPlugin.getVersion())
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
    let l:maven2TestFile = s:mvn_scriptDir.'/plugin/test/maven2testError.out'
    let l:testList = readfile(l:maven2TestFile)
    let l:mvn2Plugin = s:Mvn2Plugin.New()
    call l:mvn2Plugin.setOutputList(l:testList)
    let l:errorsDict = l:mvn2Plugin.processAtLine(60)
    call a:testR.AssertEquals('mvn2 test error message::', 13, len(l:errorsDict.quickfixList))
    call a:testR.AssertEquals('mvn2 test error message::', 'cannot find symbol symbol  : '.
            \'method setLimitDate(java.util.Date) location: '.
            \'class com.encompass.domain.inventory.InventoryDetail', l:errorsDict.quickfixList[12].text )
endfunction "}}} TestMvn2Plugin
function! s:TestMvn3Plugin(testR) "{{{ TestMvn3Plugin
    let l:maven3TestFile = s:mvn_scriptDir.'/plugin/test/maven3.out'
    let l:testList = readfile(l:maven3TestFile)
    let l:mvn3Plugin = s:Mvn3Plugin.New()
    call l:mvn3Plugin.setOutputList(l:testList)
    let l:errorsDict = l:mvn3Plugin.processAtLine(16)
    call a:testR.AssertEquals('mvn3 lineNumber in compiler output:', 20, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn3 Source file rowNum:', 9, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('mvn3 Source file colNum:', 1, l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('mvn3 Error message::', '<identifier> expected  more error message here!', l:errorsDict.quickfixList[0].text)
    let l:errorsDict = l:mvn3Plugin.processAtLine(17)
    call a:testR.AssertEquals('mvn3 lineNumber in compiler output:', 17, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('mvn3 quickfix list size:', 0, len(l:errorsDict.quickfixList))
endfunction "}}} TestMvn3Plugin
function! s:TestJunit3Plugin(testR) "{{{ TestJunit3Plugin
    let g:mvn_isTest = 0
    let &path = s:mvn_scriptDir.'/plugin/test/proj/test/src/test/java'
    let g:mvn_javaSourcePath = ''
    let g:mvn_currentPrjDict = {}
    "test mvn v3 output
    let l:testFile = s:mvn_scriptDir.'/plugin/test/maven3junit3.out'
    let l:testList = readfile(l:testFile)
    let l:junit3Plugin = s:Junit3Plugin.New()
    call a:testR.AssertEquals('junit3 type:', 'junit', l:junit3Plugin.getType())
    call l:junit3Plugin.setOutputList(l:testList)
    let l:errorsDict = l:junit3Plugin.processAtLine(35)
    call a:testR.AssertEquals('junit3 m3 lineNumber :', 72, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('junit3 m3 error count:', 3, len(l:errorsDict.quickfixList))
    call a:testR.AssertEquals('junit3 m3 Source file rowNum:', 35, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('junit3 m3 Source file colNum:', '', l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('junit3 m3 Error message::', 'java.lang.ArithmeticException: / by zero'.
        \' Easy mock error message here, and here.', l:errorsDict.quickfixList[0].text)
    "test mvn v2 output
    let l:testFile = s:mvn_scriptDir.'/plugin/test/maven2junit3.out'
    let l:testList = readfile(l:testFile)
    let l:junit3Plugin = s:Junit3Plugin.New()
    call l:junit3Plugin.setOutputList(l:testList)
    let l:errorsDict = l:junit3Plugin.processAtLine(22)
    call a:testR.AssertEquals('junit3 m2 lineNumber :', 55, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('junit3 m2 error count:', 3, len(l:errorsDict.quickfixList))
    call a:testR.AssertEquals('junit3 m2 Source file rowNum:', 35, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('junit3 m2 Source file colNum:', '', l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('junit3 m2 Error message::', 'java.lang.ArithmeticException: / by zero'.
        \' Easy mock error message here, and here.', l:errorsDict.quickfixList[0].text)

    "junit runnable output test
    let l:testFile = s:mvn_scriptDir.'/plugin/test/junit3.out'
    let l:testList = readfile(l:testFile)
    let l:quickfixList = l:junit3Plugin.processJunitOutput(testList)
    call a:testR.AssertEquals('junit3 error count:', 3, len(quickfixList))
    call a:testR.AssertEquals('junit3 Source file rowNum:', 36, quickfixList[2].lnum)
    call a:testR.AssertEquals('junit3 Source file colNum:', 0, quickfixList[2].col)
    call a:testR.AssertEquals('junit3 Error message::',
        \'1) testApp(test.AppTest)java.lang.ArithmeticException: / by zero '.
        \'EasyMock error here, and here.', quickfixList[2].text)
endfunction "}}} TestJunit3Plugin
function! s:TestJunit4Plugin(testR) "{{{ TestJunit4Plugin
    let g:mvn_isTest = 0
    let &path = s:mvn_scriptDir.'/plugin/test'
    let g:mvn_javaSourcePath = ''
    let g:mvn_currentPrjDict = {}
    "test mvn v3 output
    let l:testFile = s:mvn_scriptDir.'/plugin/test/maven3junit4.out'
    let l:testList = readfile(l:testFile)
    let l:junit4Plugin = s:Junit4Plugin.New()
    call a:testR.AssertEquals('junit4 type:', 'junit', l:junit4Plugin.getType())
    call l:junit4Plugin.setOutputList(l:testList)
    let l:errorsDict = l:junit4Plugin.processAtLine(92)
    call a:testR.AssertEquals('junit4 m3 lineNumber :', 212, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('junit4 m3 error count:', 3, len(l:errorsDict.quickfixList))
    call a:testR.AssertEquals('junit4 m3 Source file rowNum:', 19, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('junit4 m3 Source file colNum:', '', l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('junit4 m3 Error message::', 'junit.framework.AssertionFailedError EasyMock error here, '.
        \'and here.', l:errorsDict.quickfixList[0].text)
    "test mvn v2 output
    let l:testFile = s:mvn_scriptDir.'/plugin/test/maven2junit4.out'
    let l:testList = readfile(l:testFile)
    let l:junit4Plugin = s:Junit4Plugin.New()
    call l:junit4Plugin.setOutputList(l:testList)
    let l:errorsDict = l:junit4Plugin.processAtLine(65)
    call a:testR.AssertEquals('junit4 m2 lineNumber :', 183, l:errorsDict.lineNumber)
    call a:testR.AssertEquals('junit4 m2 error count:', 3, len(l:errorsDict.quickfixList))
    call a:testR.AssertEquals('junit4 m2 Source file rowNum:', 19, l:errorsDict.quickfixList[0].lnum)
    call a:testR.AssertEquals('junit4 m2 Source file colNum:', '', l:errorsDict.quickfixList[0].col)
    call a:testR.AssertEquals('junit4 m2 Error message::',
        \'junit.framework.AssertionFailedError Easy mock error message here, and here.',
        \l:errorsDict.quickfixList[0].text)
    "junit runnable output test
    let l:testFile = s:mvn_scriptDir.'/plugin/test/junit4.out'
    let l:testList = readfile(l:testFile)
    let l:quickfixList = l:junit4Plugin.processJunitOutput(testList)
    call a:testR.AssertEquals('junit4 error count:', 3, len(l:quickfixList))
    call a:testR.AssertEquals('junit4 Source file rowNum:', 19, l:quickfixList[2].lnum)
    call a:testR.AssertEquals('junit4 Source file colNum:', '', l:quickfixList[2].col)
    call a:testR.AssertEquals('junit4 Error message::',
        \'1) testComposeCompoundInventory(com.encompass.domain.inventory.InventoryUtilsTest)'.
        \'junit.framework.AssertionFailedError: null EasyMock error here, '.
        \'and here.', l:quickfixList[2].text)
    let l:pos = match(l:quickfixList[2].filename, '/plugin/')
    call a:testR.AssertEquals('junit4 file::',
        \'plugin/test/com/encompass/domain/inventory/InventoryUtilsTest.java',
        \strpart(l:quickfixList[2].filename, l:pos))
endfunction "}}} Testjunit4Plugin
function! s:TestCheckStyle22Plugin(testR) "{{{ TestCheckStyle22Plugin
    let l:checkStyleTestFile = s:mvn_scriptDir.'/plugin/test/checkstyle.out'
    let l:testList = readfile(l:checkStyleTestFile)
    let l:checkStylePlugin = s:CheckStyle22Plugin.New()
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
endfunction "}}} TestCheckStyle22Plugin
function! s:TestBuildProjectTree(testR) "{{{
    let l:mvn_testPrj = s:mvn_scriptDir."/plugin/test/proj/test"
    call system("cp -a ".l:mvn_testPrj." ".s:mvnTmpTestDir)

    let l:pomList = [s:mvnTmpTestDir.'/test/pom.xml']
    let l:prjIdPomDict = {}
    let l:prjTreeTxt = MvnBuildProjectTree(l:pomList, l:prjIdPomDict)
    call a:testR.AssertEquals('TestBuildProjectTree:', 18, len(l:prjTreeTxt))
    "TODO add test for l:prjIdPomDict and in.vim.

    let l:mvn_testPrj = s:mvn_scriptDir."/plugin/test/proj/parent"
    call system("cp -a ".l:mvn_testPrj." ".s:mvnTmpTestDir)

    let l:prjIdPomDict = {}
    let l:pomList = [s:mvnTmpTestDir.'/parent/pom.xml',
    \ s:mvnTmpTestDir.'/parent/test1/pom.xml',
    \ s:mvnTmpTestDir.'/parent/test2/pom.xml',
    \ s:mvnTmpTestDir.'/parent/test3/pom.xml']
    let l:prjTreeTxt = MvnBuildProjectTree(l:pomList, l:prjIdPomDict)
    call a:testR.AssertEquals('TestBuildProjectTree1:', 56, len(l:prjTreeTxt))
    call a:testR.AssertEquals('TestBuildProjectTree2:', 4, len(l:prjIdPomDict))

    "TODO add test for l:prjIdPomDict and in.vim.
    "call writefile(l:result.prjTreeTxt, '/tmp/mvn.txt')
endfunction "}}}
function! s:TestMvnIsInList(testR) "{{{ TestMvnIsInList
"Test object operation.
    let l:ret = MvnIsInList(['a', 'b', 'c'], "a")
    call a:testR.AssertEquals('MvnIsInList1: ', 1, l:ret)
    let l:ret = MvnIsInList(['a', 'b', 'c'], "d")
    call a:testR.AssertEquals('MvnIsInList2: ', 0, l:ret)
endfunction "}}} TestMvnIsInList
function! s:TestGetProjectDirList(testR) "{{{ TestMvnIsInList
        call system('mkdir -p '.s:mvnTmpTestDir.'/blah/')
        call system('mkdir -p '.s:mvnTmpTestDir.'/blah1/')
        call system('mkdir -p '.s:mvnTmpTestDir.'/blah2/')
        call system('mkdir -p '.s:mvnTmpTestDir.'/blah2/blah3/')
        call system('mkdir -p '.s:mvnTmpTestDir.'/blah2/blah4/')
        call system('mkdir -p '.s:mvnTmpTestDir.'/blah5/')
        call system('touch '.s:mvnTmpTestDir.'/blah/pom.xml')
        call system('touch '.s:mvnTmpTestDir.'/blah1/pom.xml')
        call system('touch '.s:mvnTmpTestDir.'/blah2/pom.xml')
        call system('touch '.s:mvnTmpTestDir.'/blah2/blah3/pom.xml')
        call system('touch '.s:mvnTmpTestDir.'/blah2/blah4/pom.xml')
        call system('touch '.s:mvnTmpTestDir.'/blah5/nopom.xml')
        silent execute 'new '.s:mvnTmpTestDir.'/.vimproject'

        "MvnGetProjectDirList(projectCount, excludeSubProjects)
        call append(0, ['blah='.s:mvnTmpTestDir.'/blah CD=. in=in.vim filter="*.vim *.java" {', '}'])
        :1
        try
            let l:dirList = MvnGetProjectDirList(1, 1)
        catch /.*/
            echo "TestGetProjectDirList1 exception: ".v:exception
        endtry
        let l:pos = match(l:dirList[0], '/mvn-ide-test/')
        call a:testR.AssertEquals('TestGetProjectDirList1:',
                \'/mvn-ide-test/blah', strpart(l:dirList[0], l:pos))

        call append(2, ['blah1='.s:mvnTmpTestDir.'/blah1 CD=. in=in.vim filter="*.vim *.java" {', '}'])
        :3
        try
            let l:dirList = MvnGetProjectDirList(1, 0)
        catch /.*/
            echo "TestGetProjectDirList2 exception: ".v:exception
        endtry
        let l:pos = match(l:dirList[0], '/mvn-ide-test/')
        call a:testR.AssertEquals('TestGetProjectDirList2:', '/mvn-ide-test/blah1',
                \strpart(l:dirList[0], l:pos))

        :1
        try
            let l:dirList = MvnGetProjectDirList(1, 0)
        catch /.*/
            echo "TestGetProjectDirList3 exception: ".v:exception
        endtry
        let l:pos = match(l:dirList[0], '/mvn-ide-test/')
        call a:testR.AssertEquals('TestGetProjectDirList3:', '/mvn-ide-test/blah',
                \strpart(l:dirList[0], l:pos))

        call append(4, ['blah2='.s:mvnTmpTestDir.'/blah2 CD=. in=in.vim filter="*.vim *.java" {',
                \' blah3='.s:mvnTmpTestDir.'/blah2/blah3 CD=. in=in.vim filter="*.vim *.java" {'
                \' }',
                \' blah4='.s:mvnTmpTestDir.'/blah2/blah4 CD=. in=in.vim filter="*.vim *.java" {'
                \' }',
                \'}',
                \'blah5='.s:mvnTmpTestDir.'/blah5 CD=. in=in.vim filter="*.vim *.java" {',
                \'}', ])

        :5
        try
            let l:dirList = MvnGetProjectDirList(1, 0)
        catch /.*/
            echo "TestGetProjectDirList4 exception: ".v:exception
        endtry
        let l:pos = match(l:dirList[0], '/mvn-ide-test/')
        call a:testR.AssertEquals('TestGetProjectDirList4 0:',
                \'/mvn-ide-test/blah2', strpart(l:dirList[0], l:pos))
        let l:pos = match(l:dirList[1], '/mvn-ide-test/')
        call a:testR.AssertEquals('TestGetProjectDirList4 1:',
                \'/mvn-ide-test/blah2/blah3', strpart(l:dirList[1], l:pos))
        let l:pos = match(l:dirList[2], '/mvn-ide-test/')
        call a:testR.AssertEquals('TestGetProjectDirList4 2:',
                \'/mvn-ide-test/blah2/blah4', strpart(l:dirList[2], l:pos))
        bd!
endfunction "}}} TestMvnIsInList
function! s:TestEnvBuild(testR) "{{{ TestEnvBuild
"Test the generation of the project tree.

    if exists('g:proj_running')
        let l:proj_running = g:proj_running
    else
        let l:proj_running = -1
    endif

    try
        let l:mvn_testPrj = s:mvn_scriptDir."/plugin/test/proj/test1"

        silent execute 'new '.s:mvnTmpTestDir.'/.vimproject'
        let g:proj_running = bufnr('%')
        let l:prjIdPomFilename= bufname('%')."-mvn-ide"

        call system("cp -a ".l:mvn_testPrj." ".s:mvnTmpTestDir)
        let l:testHome = s:mvnTmpTestDir."/test1"
        call MvnInsertProjectTree(l:testHome)
        "Test with the custom in.vim configuration.
        call a:testR.AssertEquals('Mvn src location: ', ' srcMain=src/m/java {', getline(3))
        call a:testR.AssertEquals('Mvn test src location: ', ' srcTest=src/t/java {', getline(11))
        call a:testR.AssertEquals('Mvn main resource location: ', ' resrcMain=src/m/r {', getline(15))
        call a:testR.AssertEquals('Mvn test resource location: ', ' resrcTest=src/t/r {', getline(17))

        let l:prjIdPomDict = eval(readfile(l:prjIdPomFilename)[0])
        call a:testR.AssertEquals('Sibling project identifiers1: ',
            \type({}), type(l:prjIdPomDict))
        call a:testR.AssertEquals('Sibling project identifiers2: ',
                \'test:test1:1.0', l:prjIdPomDict['test:test1:1.0']['id'])

        "Get the maven repo directory.
        let l:effectiveSettingsFile = s:mvn_tmpdir."/effective-settings.xml"
        let l:effectiveSettings = system("cd ".l:testHome."; "
            \."mvn org.apache.maven.plugins:maven-help-plugin:"
            \."2.1.1:effective-settings")
        let l:effectiveSettings = MvnTrimStringPre(l:effectiveSettings, "<settings ")
        let l:effectiveSettings = MvnTrimStringPost(l:effectiveSettings, "</settings>")
        let l:effectiveSettings = substitute(l:effectiveSettings, "\n", "", "g")
        call writefile([l:effectiveSettings], l:effectiveSettingsFile)
        let l:query = "/settings/localRepository/text\(\)"
        let l:rawNodeList = MvnGetXPath(l:effectiveSettingsFile, l:query)
        let l:mvnRepoDir = MvnParseNodesToList(l:rawNodeList)[0]

        if !filereadable(l:mvnRepoDir.'/junit/junit/3.8.2/junit-3.8.2.jar') ||
            \!filereadable(l:mvnRepoDir.'/junit/junit/3.8.2/junit-3.8.2-sources.jar')
            "make sure the junit javadoc and source exists.
            let l:cmd = "cd ".l:testHome
            let l:cmd .= "; mvn org.apache.maven.plugins:maven-dependency-plugin:2.1:"
            let l:cmd .= "resolve -Dclassifier=javadoc"
            let l:cmd .= " org.apache.maven.plugins:maven-dependency-plugin:2.1:"
            let l:cmd .= "sources"
            let l:output = system(l:cmd)
        endif

        "position the cursor.
        :2
        call MvnCreateEnv(l:testHome, {}, '/dummy/jre/path')

        "Check the configuration in in.vim.
        let l:inVimList = readfile(l:testHome.'/in.vim')
        let l:line = get(l:inVimList, 0)
        let l:currentPrjDict = eval(strpart(l:line, matchend(l:line, '=')))
        call a:testR.AssertEquals('Test in.vim g:mvn_currentPrjDict',
            \'test:test1:1.0', l:currentPrjDict['id'])
        call a:testR.AssertEquals('Test in.vim vjde_lib_path',
            \'let g:vjde_lib_path="'.l:currentPrjDict['classMain'][0].':/dummy/jre/path:'
            \.l:mvnRepoDir.'/junit/junit/3.8.2/junit-3.8.2.jar"',
            \get(l:inVimList, 1))
        call a:testR.AssertEquals('Test in.vim source path',
            \'let g:mvn_javaSourcePath="'.l:testHome.'/src/m/java:'.g:mvn_javaSourceParentDir.
            \'/junit-3.8.2:'.g:mvn_additionalJavaSourcePath.'"',
            \get(l:inVimList, 2))
        call a:testR.AssertEquals('Test in.vim javadoc path',
            \'let g:mvn_javadocPath="'.g:mvn_javadocParentDir.
            \'/junit-3.8.2:'.g:mvn_additionalJavadocPath.'"',
            \get(l:inVimList, 3))
        let l:runLib = MvnGetJreRuntimeLib()
        call a:testR.AssertEquals('Test MvnGetJreRuntimeLib() is readable: '.
            \l:runLib,
            \1, filereadable(l:runLib))
        bd!
    finally
        if l:proj_running != -1
            let g:proj_running = l:proj_running
        else
            unlet g:proj_running
        endif
    endtry
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
        \[l:testPrj.'/src/m/java'], l:mvnPomDict['srcMain'])
    call a:testR.AssertEquals('CreatePomDict srcTest: ',
        \[l:testPrj.'/src/t/java'], l:mvnPomDict['srcTest'])
    call a:testR.AssertEquals('CreatePomDict classMain: ',
        \[l:testPrj.'/t/classes'], l:mvnPomDict['classMain'])
    call a:testR.AssertEquals('CreatePomDict classTest: ',
        \[l:testPrj.'/t/test-classes'], l:mvnPomDict['classTest'])
    call a:testR.AssertEquals('CreatePomDict resrcMain: ',
        \[l:testPrj.'/src/m/r'], l:mvnPomDict['resrcMain'])
    call a:testR.AssertEquals('CreatePomDict resrcTest: ',
        \[l:testPrj.'/src/t/r'], l:mvnPomDict['resrcTest'])
endfunction "}}} TestCreatePomDict
function! s:TestGetPomDetailDict(testR) "{{{
"Check existing elements in prjIdPomDict are preserved.
    new
    let l:mvn_testPrj = s:mvn_scriptDir."/plugin/test/proj/test1"
    call system("cp -a ".l:mvn_testPrj." ".s:mvnTmpTestDir)
    let l:testHome = s:mvnTmpTestDir."/test1"
    let l:prjIdPomDict = {'dummy': 'dummy'}
    call MvnGetPrjPomDict(l:testHome, l:prjIdPomDict, 1)
    call a:testR.AssertEquals('MvnGetPomDetailDict: ', 2, len(l:prjIdPomDict))
    bd!
    "TODO check the result.
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
    let l:pos = matchend(l:rawNodeList[2],'/plugin/')
    call a:testR.AssertEquals('MvnGetXPathFromPom3: ',
        \'test/proj/test1/src/m/java',
        \strpart(l:rawNodeList[2], l:pos))
    let l:nodeList = MvnParseNodesToList(l:rawNodeList)
    let l:pos = matchend(l:nodeList[0],'/plugin/')
    call a:testR.AssertEquals('ParseSrcNodes: ',
        \"test/proj/test1/src/m/java",
        \strpart(l:nodeList[0], l:pos))
endfunction "}}} TestMvnGetXPath
function! s:TestGetPomId(testR) "{{{ TestMvnGetPomId
    let l:effectivePom = s:mvn_scriptDir."/plugin/test/xml/effective-pom.xml"
    let l:id = MvnGetPomId(l:effectivePom)
    call a:testR.AssertEquals('MvnGetPomId: ', 'test:test1:1.0', l:id)
endfunction "}}} TestMvnGetPomId
function! s:TestGetVimInDict(testR) "{{{ TestMvnVimInDict
    let l:invim= s:mvn_scriptDir."/plugin/test/test_in_vim"
    let l:projectDict = MvnLoadPrjPomDict(l:invim)
    call a:testR.AssertEquals('MvnVimInDict: ', {'id': 'test:test:1.0'}, l:projectDict)
endfunction "}}}
function! s:TestGetTagFileDir(testR) "{{{
    let l:srcPath = '/a/c/d/e'
    let l:prjPomDict = {'home': '/a', 'srcMain': ['/a/b'], 'srcTest': ['/a/c/d']}
    let l:tagfile = MvnGetTagFileDir(l:srcPath, l:prjPomDict)
    call a:testR.AssertEquals('MvnGetTagFileDir1: ', '/a/tags-t', l:tagfile)
    let l:srcPath = '/a/b/c'
    let l:tagfile = MvnGetTagFileDir(l:srcPath, l:prjPomDict)
    call a:testR.AssertEquals('MvnGetTagFileDir2: ', '/a/tags', l:tagfile)
    let l:srcPath = '/b/c/d'
    let l:tagfile = MvnGetTagFileDir(l:srcPath, l:prjPomDict)
    call a:testR.AssertEquals('MvnGetTagFileDir3: ', '/b/c/d/tags', l:tagfile)
endfunction "}}}
function! s:TestFileIsChild(testR) "{{{
    let isChild = MvnFileIsChild(['/a/b/c', '/a/d/e'], '/a/g/h')
    call a:testR.AssertEquals('MvnTestFileIsChild: ', l:isChild, 0)
    let isChild = MvnFileIsChild(['/a/b/c', '/a/d/e'], '/a/b/c/d')
    call a:testR.AssertEquals('MvnTestFileIsChild1: ', l:isChild, 1)
    let isChild = MvnFileIsChild(['/a/b/c', '/a/d/e'], '/a/d/e')
    call a:testR.AssertEquals('MvnTestFileIsChild2: ', l:isChild, 1)
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
    call sort(l:subDirs)
    call a:testR.AssertEquals('MvnInstallJavadoc test find: ', ['META-INF', 'mvn-ide-test', 'mvnidetest'], l:subDirs)

    for dir in l:dirList
        let dirPathList = split(dir, '/')
        let l:name = dirPathList[len(dirPathList)-1]
        call add(l:subDirs, l:name)
    endfor
    "test the build of javadoc
    call system('mkdir -p '. s:mvnTmpTestDir.'/javadoc')
    let l:jdPath = MvnInstallJavadocFromSource(s:mvnTmpTestDir.'/javadoc',
        \s:mvn_scriptDir.'/plugin/test/javadoc/src',
        \['/blah/blah/mvn-ide-test-sources.jar'], [])
    call a:testR.AssertEquals('MvnInstallJavadoc: ', s:mvnTmpTestDir.'/javadoc/mvn-ide-test',
        \l:jdPath)
endfunction; "}}}
function! s:TestUpdateFile(testR) "{{{
   "TODO finish
    let l:filename = s:mvnTmpTestDir.'/test-in.vim'
    call MvnUpdateFile(l:filename, 'blah', 'blah')
    let l:buf = readfile(l:filename)
    call a:testR.AssertEquals('TestSetEnv0: ', 'blah', l:buf[0])
    call a:testR.AssertEquals('TestSetEnv1: ', 'call MvnSetEnv()', l:buf[1])

    call add(l:buf, remove(l:buf, 0))
    call writefile(l:buf, l:filename)
    call MvnUpdateFile(l:filename, 'blah', 'blah')
    let l:buf = readfile(l:filename)
    call a:testR.AssertEquals('TestSetEnv2: ', 'blah', l:buf[0])
    call a:testR.AssertEquals('TestSetEnv3: ', 'call MvnSetEnv()', l:buf[1])
endfunction; "}}}
function! s:TestGetClassFromFilename(testR) "{{{
    let l:prjDict = {'home': '/opt/prj', 'srcMain': ['/opt/proj/src/main/java'], 'srcTest': ['/opt/proj/src/test/java']}
    let l:result = MvnGetClassFromFilename("/opt/proj/src/main/java/pack/age/Dummy.java", l:prjDict)
    call a:testR.AssertEquals('MvnGetClassFromFilename1 fail:', "pack.age.Dummy", l:result)
    let l:result = MvnGetClassFromFilename("/opt/proj/src/test/java/pack/age/Dummy.java", l:prjDict)
    call a:testR.AssertEquals('MvnGetClassFromFilename2 fail:', "pack.age.Dummy", l:result)
endfunction "}}}
function! s:TestSetEnv(testR) "{{{
    let l:prjPomDict = {'srcMain': [s:mvnTmpTestDir.'/a/b/c'], 'srcTest': [s:mvnTmpTestDir.'/a/b/d'], 'home': s:mvnTmpTestDir.'/a/b', 'classTest': [s:mvnTmpTestDir.'/a/b/target/test']}
    let l:srcFile = s:mvnTmpTestDir.'/a/b/c/d.txt'
    let g:vjde_lib_path = ''
    let g:mvn_javaSourcePath = ''
    let &path = ''
    let &tags = ''
    let g:mvn_isTest = 1

    call MvnSetEnv(l:srcFile, l:prjPomDict, 'txt')
    call a:testR.AssertEquals('TestSetEnv0: ', 0, g:mvn_isTest)
    call a:testR.AssertEquals('TestSetEnv1: ', '', g:vjde_lib_path.g:mvn_javaSourcePath.&tags)

    let l:srcFile = s:mvnTmpTestDir.'/a/b/d/d.txt'
    call system('mkdir -p '.s:mvnTmpTestDir.'/a/b; touch '. s:mvnTmpTestDir.'/a/b/tags-t')
    call MvnSetEnv(l:srcFile, l:prjPomDict, 'txt')
    call a:testR.AssertEquals('TestSetEnv2: ', 1, g:mvn_isTest)
    call a:testR.AssertEquals('TestSetEnv3: ', s:mvnTmpTestDir.'/a/b/target/test:', g:vjde_lib_path)
    call a:testR.AssertEquals('TestSetEnv4: ', s:mvnTmpTestDir.'/a/b/d:', g:mvn_javaSourcePath)
    call a:testR.AssertEquals('TestSetEnv5: ', s:mvnTmpTestDir.'/a/b/d/**,', &path)
    call a:testR.AssertEquals('TestSetEnv6: ', s:mvnTmpTestDir.'/a/b/tags-t,', &tags)
endfunction; "}}}
function! s:TestDirectorySort(testR) "{{{
"0 -equal, 1 - dir1 sorts after dir2, -1 - dir1 sorts before dir2.
    let l:ret = MvnDirectorySort('/a/b/c/p', '/a/b/c/d/e')
    call a:testR.AssertEquals('MvnDirectorySort1', -1, l:ret)
    let l:ret = MvnDirectorySort('/a/b/c/d/e', '/a/b/c/p')
    call a:testR.AssertEquals('MvnDirectorySort2', 1, l:ret)
    let l:ret = MvnDirectorySort('/a/b/c', '/a/b/c')
    call a:testR.AssertEquals('MvnDirectorySort3', -1, l:ret)
    let l:Fn = function("MvnDirectorySort")
    let l:tmpList = sort(['/a/b/c/p', '/a/b/p', '/a/b/c/d', '/a'], l:Fn)
    let l:expected =['/a', '/a/b/p', '/a/b/c/p', '/a/b/c/d']
    call a:testR.AssertEquals('MvnDirectorySort4', l:expected, l:tmpList)
    let l:tmpList = sort(['/z','/b','/c','/p','/d','/e','/f','/g','/h','/i','/j','/a'], l:Fn)
    call a:testR.AssertEquals('MvnDirectorySort5', '/z', l:tmpList[0])
    call a:testR.AssertEquals('MvnDirectorySort6', '/p', l:tmpList[1])
    call a:testR.AssertEquals('MvnDirectorySort7', '/a', l:tmpList[11])
    let l:dirList = ['./encompass-web/web', './encompass-web',
        \'./common/schema', './common/service', './common/domain',
        \'./common/data', './common/util',
        \'./common', '.']
    let l:expected = [ [ '.' ], [ './encompass-web', './common',
        \'./encompass-web/web', './common/util', './common/service',
        \'./common/schema', './common/domain','./common/data' ] ]
    let l:lists = MvnDirectoryParentChildSplit(l:dirList)
    call a:testR.AssertEquals('MvnDirectorySort8', l:expected, l:lists)

    let l:pomList = ['./encompass-web/web/pom.xml', './encompass-web/pom.xml',
        \'./common/schema/pom.xml', './common/service/pom.xml', './common/domain/pom.xml',
        \'./common/data/pom.xml', './common/util/pom.xml',
        \'./common/pom.xml', './pom.xml']

    let l:sortedPoms = MvnPomFileOrdering(l:pomList)
    let l:expected = [ './pom.xml', './common/pom.xml',
        \'./common/data/pom.xml', './common/domain/pom.xml',
        \'./common/schema/pom.xml', './common/service/pom.xml','./common/util/pom.xml',
        \'./encompass-web/pom.xml', './encompass-web/web/pom.xml' ]
    call a:testR.AssertEquals('MvnDirectorySort9', l:expected, l:sortedPoms)
endfunction "}}}
function! s:TestIsTestSrc(testR) "{{{
    if !exists('g:proj_running')
        throw "Please run :Project before the test execution."
    endif
    let l:prjPomDict = {'srcMain': ['a/b/c'], 'srcTest': ['x/y/z'], 'home': '123'}
    let l:srcFile = 'a/b/c/d.txt'
    let l:isTest = MvnIsTestSrc(l:srcFile, l:prjPomDict)
    call a:testR.AssertEquals('TestIsTestSrc0: ', 0, l:isTest)

    let l:tmpProj = g:proj_running
    let g:proj_running = -1
    let l:prjPomDict = {'srcMain': ['/a/b/c'], 'srcTest': ['x/y/z'], 'home': '123'}
    try
        let l:isTest = MvnIsTestSrc(l:srcFile, l:prjPomDict)
    catch /Source file */
       let l:isTest = -2
    endtry
    let g:proj_running = l:tmpProj
    call a:testR.AssertEquals('TestIsTestSrc1: ', -2, l:isTest)

    let l:srcFile = 'x/y/z/a/b/c/d.txt'
    let l:isTest = MvnIsTestSrc(l:srcFile, l:prjPomDict)
    call a:testR.AssertEquals('TestIsTestSrc2: ', 1, l:isTest)

    let l:srcFile = '123/d.txt'
    let l:isTest = MvnIsTestSrc(l:srcFile, l:prjPomDict)
    call a:testR.AssertEquals('TestIsTestSrc3: ', 0, l:isTest)
endfunction; "}}}
function! s:TestExecutable(filename) "{{{
    let l:bin = system('which '.a:filename)
    if len(l:bin) == 0
        throw "No ".a:filename." in shell execution path."
    else
        let l:endPos = matchend(l:bin, '[\n\r]')
        let l:bin = strpart(l:bin, 0, l:endPos - 1)
        if !executable(l:bin)
            throw "File ".a:filename." at ".l:bin." not executable."
        endif
    endif
endfunction "}}}
function! s:TestDependencies(dummy) "{{{
    "Show the vim features with #vim --version or :version from the vim prompt.
    call s:TestExecutable('java')
    call s:TestExecutable('mvn')
    call s:TestExecutable('perl')
    call s:TestExecutable('find')
    call s:TestExecutable('yavdb')
    call s:TestExecutable('ex')
    let l:xpathSuccess= system('perl -MXML::XPath -e 1')
    if len(l:xpathSuccess) > 0
        throw 'No perl XML::XPath module. Check maven-ide installation instructions.'
    endif
    if !has('python')
        throw 'Require python feature. Run :version'
    endif
    if len($USER) == 0
        throw 'Environment $USER is required.'
    endif
    if !exists('*VDBIsConnected')
        echo 'yavdb not patched?'
    endif
    if !has('clientserver')
        echo  'No clientserver. Run :version'
    endif
endfunction; "}}}
function! s:TestSetup() "{{{
    if exists('g:mvn_isTest')
        let s:orig_mvn_isTest = g:mvn_isTest
    endif
    if exists('g:mvn_javaSourcePath')
        let s:orig_mvn_javaSourcePath = g:mvn_javaSourcePath
    endif
    if exists('g:mvn_currentPrjDict')
        let s:orig_mvn_currentPrjDict = g:mvn_currentPrjDict
    endif
    if exists('&path')
        let s:origPath = &path
    endif
    let s:mvnTmpTestDir = s:mvn_tmpdir."/mvn-ide-test"
    call system("mkdir -p ".s:mvnTmpTestDir)
endfunction; "}}}
function! s:TestTearDown() "{{{
    call system("rm -r ".s:mvnTmpTestDir)
    unlet s:mvnTmpTestDir
    if exists('s:orig_mvn_isTest')
        let g:mvn_isTest = s:orig_mvn_isTest
        unlet s:orig_mvn_isTest
    endif
    if exists('s:orig_mvn_javaSourcePath')
        let g:mvn_javaSourcePath = s:orig_mvn_javaSourcePath
        unlet s:orig_mvn_javaSourcePath
    endif
    if exists('s:orig_mvn_currentPrjDict')
        let g:mvn_currentPrjDict = s:orig_mvn_currentPrjDict
        unlet s:orig_mvn_currentPrjDict
    endif
    if exists('s:origPath')
        let &path = s:origPath
        unlet s:origPath
    endif
endfunction; "}}}
function! MvnRunTests() "{{{ MvnRunTests
    let s:mvn_inUnitTest = 1
    try
        let l:testR = s:TestRunner.New()
        call s:TestSetup()
        "{{{ misc tests
        call s:TestDependencies(l:testR)
        call s:TestMvnIsInList(l:testR)
        call s:TestFileIsChild(l:testR)
        call s:TestGetTagFileDir(l:testR)
        "}}} misc tests
        "{{{ xml tests
        call s:TestMvnGetXPath(l:testR)
        call s:TestMvnGetXPathFromTxt(l:testR)
        "}}} xml tests
        "{{{ plugin tests
        call s:TestPluginObj(l:testR)
        call s:TestMvn2Plugin(l:testR)
        call s:TestMvn3Plugin(l:testR)
        call s:TestCheckStyle22Plugin(l:testR)
        call s:TestJunit3Plugin(l:testR)
        call s:TestJunit4Plugin(l:testR)
        "}}} plugin tests
        "{{{ Tree/Env Build
        call s:TestUpdateFile(l:testR)
        call s:TestIsTestSrc(l:testR)
        call s:TestSetEnv(l:testR)
        call s:TestGetClassFromFilename(testR)
        call s:TestDirectorySort(testR)
        call s:TestBuildProjectTree(l:testR)
        call s:TestCreatePomDict(l:testR)
        call s:TestGetPomId(l:testR)
        call s:TestGetVimInDict(l:testR)
        call s:TestIdFromJarName(l:testR)
        call s:TestClasspathPreen(testR)
        call s:TestInstallJavadocFromSource(testR)
        call s:TestGetPomDetailDict(testR)
        call s:TestGetProjectDirList(testR)
        call s:TestEnvBuild(testR)
        "}}} Tree/Env Build
        call l:testR.PrintStats()
        call s:TestTearDown()
    finally
        let s:mvn_inUnitTest = 0
    endtry
endfunction; "}}} MvnRunTests
function! MvnRunSingleTest(testFuncName) "{{{ MvnCallTest
"Useful during test development.
"a:testFuncName - a string containing the script function name of the test
"   function without the 's:' prefix.
    let s:mvn_inUnitTest = 1
    try
        call s:TestSetup()
        let l:testR = s:TestRunner.New()
        let TestFun = function('s:'.a:testFuncName)
        call TestFun(l:testR)
        call l:testR.PrintStats()
        call s:TestTearDown()
    finally
        let s:mvn_inUnitTest = 0
    endtry
endfunction; "}}} MvnCallTest
"}}} Tests --------------------------------------------------------------------

"{{{ Coding -------------------------------------------------------------------
function! MvnCodeFormat() "{{{
"Format the current file.
"{{{ body
    let save_cursor = getpos(".")
    "Remove all end of line spaces.
    :1,$:s/ \+$//g
    "Replace all tabs with spaces.
    let l:ts_spaces = &tabstop
    exec ':1,$:s/\t/' . repeat(' ', l:ts_spaces) . '/g'
    call setpos('.', save_cursor)
endfunction; "}}} body }}}
function! MvnPrintCodes() "{{{
"Print Codes
"Enter the codes with: CTRL-v ddd
"   where the ddd are the 3 digit code.
"{{{ body
    new
    let l:list = []
    let l:indx = 0
    let l:lineCnt = 30
    let l:space = 4
    while l:indx < 2048
        if l:indx == 0
            let l:char = 'NUL'
        elseif l:indx == 9
            let l:char = '\t'
        else
            let l:char = nr2char(l:indx)
        endif
        let l:displayWidth = strdisplaywidth(l:char)
        let l:spaceAdj = l:space - l:displayWidth
        call add(l:list, printf('%-3d %-1s'.repeat(' ',l:spaceAdj), l:indx, l:char))
        let l:indx += 1
    endwhile
    let l:page = []
    let l:maxRows = l:lineCnt
    let l:indx = 0
    while l:indx < l:lineCnt
        call add(l:page, '')
        let l:indx += 1
    endwhile
    let l:indx = 0
    for l:val in l:list
        let l:page[l:indx%l:lineCnt] .= l:val
        let l:indx += 1
    endfor
    call append(0, l:page)
endfunction; "}}} body }}}
"}}} Coding -------------------------------------------------------------------

"{{{ Key mappings -------------------------------------------------------------
map \ce :call MvnCreateEnvSelection() <RETURN>
map \bp :call MvnInsertProjectTree("") <RETURN>
map \bt :call MvnTagCurrentFile() <RETURN>
map \cf :call MvnCodeFormat() <RETURN>
map \dd :call MvnDownloadJavadoc() <RETURN>
map \ds :call MvnDownloadJavaSource() <RETURN>
map \fc :call MvnFindJavaClass() <RETURN>
map \fs :call MvnFindSubclass(expand("<cword>")) <RETURN>
map \gt :call MvnJumpToTree() <RETURN>
map \pc :call MvnPrintCodes() <RETURN>
map \ps :call MvnPickInherits() <RETURN>
map \mo :call MvnSetOffline() <RETURN>
map \rm :call MvnCompile() <RETURN>
map \rj :call MvnJavacCompile() <RETURN>
map \rd :call MvnDoDebug() <RETURN>
map \rt :call MvnRunJunit() <RETURN>
map \rp :call MvnRefreshPrjIdPomDict() <RETURN>
map \sd :call MvnOpenJavaDoc(g:mvn_javadocPath) <RETURN>
map \so :call MvnShowMavenOutput() <RETURN>
"}}} Key mappings -------------------------------------------------------------

"{{{ Public Variables ---------------------------------------------------------
set cfu=VjdeCompletionFun
"let g:vjde_lib_path = generated into in.vim
"let g:mvn_currentPrjDict = generated into in.vim
"let g:mvn_javadocPath = generated into in.vim
"let g:mvn_javaSourcePath = generated into in.vim
"let &tags = generated into in.vim
"let &path  = generated into in.vim
"let g:mvn_isTest = set in MvnSetEnv()

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
if !exists('g:mvn_debugPortList')
    let g:mvn_debugPortList = ['8888','11550','dev.localdomain:11550']
endif
if !exists('g:mvn_pluginList')
    let g:mvn_pluginList = ['Mvn2Plugin', 'Junit3Plugin', 'CheckStyle22Plugin']
endif
if !exists('g:mvn_compilerVersion')
    let g:mvn_compilerVersion = '2.5.1'
endif
"{{{ Private Variables --------------------------------------------------------
"TODO remove this func?
function! s:MvnDefaultPrjEnvVars()
    let s:mvn_projectMainWebapp="src/main/webapp"
endfunction
call s:MvnDefaultPrjEnvVars()

let s:mvn_kernel = matchstr(system("uname -s"), '\w\+')
if s:mvn_kernel =~ "FreeBSD"
"   let s:mvn_xpathcmd = "xpath filename \"query\""
   let s:mvn_tagprg = "exctags"
elseif s:mvn_kernel == "Linux"
"   let s:mvn_xpathcmd = "xpath -e \"query\" filename"
   let s:mvn_tagprg = "ctags"
endif
let s:mvn_tmpdir = resolve("/tmp")."/".$USER
call system("mkdir -p ".s:mvn_tmpdir)
let s:mvn_defaultProject = ""
let s:mvn_scriptFile = expand("<sfile>")
let s:mvn_scriptDir = strpart(s:mvn_scriptFile, 0,
        \ match(s:mvn_scriptFile, "/plugin/"))
let s:mvn_xpathcmd = "perl -w ".s:mvn_scriptDir.
        \"/bin/xpath.pl filename \"query\""
let s:plugins = MvnPluginInit()
let s:mvn_inUnitTest = 0
function! MvnSetOffline()
    if !exists('s:mvn_offline') || len(s:mvn_offline) > 0
        if exists('s:mvn_offline')
            echo 'Maven online.'
        endif
        let s:mvn_offline = ''
    else
        let s:mvn_offline = '-o'
        echo 'Maven offline.'
    endif
    let s:mvnCmd = "mvn ".s:mvn_offline.
        \" -fn org.apache.maven.plugins:maven-dependency-plugin:2.4:build-classpath".
        \" org.apache.maven.plugins:maven-help-plugin:2.1.1:effective-pom"
endfunction;
call MvnSetOffline()
"}}} Private Variables  -------------------------------------------------------
"}}} Public Variables ---------------------------------------------------------

" vim:ts=4:sw=4:expandtab:tw=78:ft=vim:fdm=marker:
