:au BufnewFile,BufRead *.java call LoadMvnIde()
let s:mvn_scriptFile = expand("<sfile>")

function LoadMvnIde()
  if exists("g:mvn_loaded")
  else
    let g:mvn_loaded = 1
    let l:mvn_scriptDir = strpart(s:mvn_scriptFile, 0,
              \ match(s:mvn_scriptFile, "/plugin/"))
    let l:mvnScript = l:mvn_scriptDir."/script/maven-ide.vim"
    exec "source ".l:mvnScript
    echo 'Load maven-ide complete.'
  endif
endfunction

