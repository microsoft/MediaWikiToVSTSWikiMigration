param(
    [string]$pageName, 
    [string]$pagePath, 
    [string]$templateName,
    [string]$templatePath,
    [string]$mediawikiDomain
)

$variablesPath  = $PSScriptRoot + '\.\Variables.ps1'
. $variablesPath

$mailToOrg = '@microsoft.com'
$mediaWikiPageNameKeyword = "PAGENAME"

function preProcessPage($path, $pageName) {
    $content = Get-Content $path -Raw
    $content = preProcessPageContent -content $content -pageName $pageName
    Set-Content -Path $path -Value $content
}

function preprocessTemplate($path, $pageName) {
    $content = Get-Content $path -Raw
    $content = preProcessTemplateContent -content $content
    $content = preProcessPageContent -content $content -pageName $pageName
    Set-Content -Path $path -Value $content
}

function preProcessPageContent($content, $pageName) {
    ## replace [[http...]] with [http...] for pandoc to migrate correclty
    $content = $content -replace '(\[\[http)(((?!\]\]).)*)(\]\])','[http$2]'
    ## replace [[file:...]] with [[File:...]] for pandoc to migrate correclty
    $content = $content -replace '(\[\[file:)(((?!\]\]).)*)(\]\])','[[File:$2]]'
    # usually we dont show no-include content for templates but for content pages, show no include content as well
    $content = $content -replace '<noinclude>((.|\n)*?)<\/noinclude>','$1' 
    #remove includeonly tag and preserve its content
    $content = $content -replace '<includeonly>((.|\n)*?)<\/includeonly>','$1'
    #handle some common mistakes that pandoc does not understand
    $content = $content -replace '\|framed\|','|frame|'
    $content = $content -replace '\|framed\]\]','|frame]]'  

    $content = parseLineByLine $content
    $content = handleMailToBlocks $content
    $content = handleExternalLink $content
    $content = handleTemplates -content $content -pageName $pageName

    return $content
}

function handleMailToBlocks($content) {
    #make the content in pandoc understandable format
    If($mailToOrg) {
        $regexStr = '(\[mailto:)(((?!' + $mailToOrg + '|\]|\s).)*)\s+([^\]]*)\]'
        $replaceStr = '[mailto:$2' + $mailToOrg +  ' $4]'
        return $content -replace $regexStr, $replaceStr
    }

    return $content
}

function handleExternalLink($content) {
    $splitArr = $content -split '(\[https:\/\/)(.*?)(\s)(.*?)(\])'
    $indexToModify = 2
    While($indexToModify -lt $splitArr.Count) {
        If(-Not $splitArr[$indexToModify].StartsWith($mediawikiDomain)) {
            
            $splitArr[$indexToModify] = [System.Net.WebUtility]::UrlEncode($splitArr[$indexToModify])
            # these are some of the commo  characters that url encode did not encode (but decoder decoded correclty)
            $splitArr[$indexToModify] = $splitArr[$indexToModify] -replace  '\(','%5C%28' # add ecaping
            $splitArr[$indexToModify] = $splitArr[$indexToModify] -replace '\)','%5C%29' # add ecaping
            $splitArr[$indexToModify] = $splitArr[$indexToModify] -replace '\!','%21'
            $splitArr[$indexToModify] = $splitArr[$indexToModify] -replace '\*','%2A'  
                         
            }
            $indexToModify = $indexToModify + 6         
    }

    $newContent = ''
    $newContent = $splitArr -join '' # FORM THE COMPLETE URL AGAIN

    return $newContent
}

#handles template calls inside any page (could be another template also)
function handleTemplates($content,$pageName) {
    # detect a template
    $regexArr = $content -split '{{((.|\n)*?)}}'
    $newContent = ''
    $nextValidIdx = 1
    $nextSkipIdx = $nextValidIdx + 1
    $currIdx = 0

    While($currIdx -lt $regexArr.Length) {
        
        if($currIdx -eq $nextValidIdx) {

            # normal pages can be used as tempaltes
            # detect that
            # BEFORE:
            # {{Template:name}}, {{name}} is a temaplte
            # {{:name}} is any other page
            # {{:Category:name}} is a category used as a tempalte
            # AFTER
            # {{Template:name}}is definately a temaplte
            # {{name}} is any other page
            # Category is not handled
            if($regexArr[$currIdx].StartsWith($mediaWikiTemplatePrefix, "CurrentCultureIgnoreCase")) {
                #removing it to avid case misatches later
                $regexArr[$currIdx] = $regexArr[$currIdx].Remove(0, $mediaWikiTemplatePrefix.Length)
                #standardize with Template:
                $regexArr[$currIdx] = $mediaWikiTemplatePrefix + $regexArr[$currIdx]

            } elseif($regexArr[$currIdx].StartsWith(':')){
                # this is a page or category name
                $regexArr[$currIdx] = $regexArr[$currIdx].TrimStart(':')
            } elseif($regexArr[$currIdx].Trim() -ne $mediaWikiPageNameKeyword){ # {{PAGENAME}} is a magic syntax - dont confuse it as a tempalte
                # this is also a atemplate - add template to the name
                $regexArr[$currIdx] = $mediaWikiTemplatePrefix + $regexArr[$currIdx]
            }

            # Page section not supported in template syntax
            # side effect: #if... is also pruned
            $regexArrPipe = $regexArr[$currIdx] -split '\|'
            if($regexArrPipe[0].Contains('#')){ 
                $regexArrPipe[0] = ($regexArrPipe[0] -split '#')[0]
            }
            $regexArr[$currIdx] = $regexArrPipe -join '|'

            # add pagename to the syntax if not already there
            # also change the temaplte syntax from {{name}} to {{(name)}} - this is to fool pandoc
            # otherwise it prunes temapltes from content
            if($regexArr[$currIdx].Contains($mediaWikiPageNameKeyword))  {
                $regexArr[$currIdx] = '{{(' + $regexArr[$currIdx] + ')}}'
            }else {
                $regexArr[$currIdx] = '{{(' + $regexArr[$currIdx] + '| ' + $mediaWikiPageNameKeyword + '=' + $pageName + ')}}'
            }
            $nextValidIdx = $nextValidIdx + 3

        }
        
        if($currIdx -eq $nextSkipIdx) {
            $nextSkipIdx = $nextSkipIdx + 3
        }
        else {
            $newContent = $newContent + $regexArr[$currIdx]
        }

        $currIdx++
    } 

    return $newContent
}

# only checks if the curent line is a <space>*<content>
#urls or image text are not considered as code lines
function isLineMediaWikiCodeBlock($line) {
    # images and url are not supported inside code blocks

    If(-not $line) {
        return $false
    }

    $hasUrlOrImageText = $line.Contains('[[')
    $isCodeBlock = $line.StartsWith(' ') -and $line.Trim(' ') -ne '' -and -not $hasUrlOrImageText

    return $isCodeBlock
}

#not a foolproof method - avoid using outside of this scope
function isLineHtml($line) {
    return $line.Contains('<span') -or $line.Contains('<code') -or $line.Contains('<div') -or $line.Contains('<code')
}

#loophole - if a line contains more than one tag, we check for ending tag for just one
function isLineHtmlCodeBlockStart($line) {
   return $line.Contains('<pre') -or  $line.Contains('<code') -or $line.Contains('<source') -or $line.Contains('<syntaxhighlight')
}

function parseLineByLine($content) {
    #split the content in newline and parse each line
    $result = $content -split "`n"
    $codeBlockStart = -1
    $len = $result.Length
    For($ctr = 0; $ctr -lt $len; $ctr++) {
        $line = $result[$ctr]
        $isLineHtmlCodeBlockStart = isLineHtmlCodeBlockStart $line
        $isWikiTableInProgress = $false

        If($line -ne $Null) {
            if($isLineHtmlCodeBlockStart -or $line.Contains('{| class="wikitable" ')) {
                $closingTag = ''
                if($line.Contains('<pre')) { $closingTag =  '</pre>' }
                elseif($line.Contains('<code')) { $closingTag =  '</code>'  }
                elseif($line.Contains('<source')) {  $closingTag =  '</source>' }
                elseif($line.Contains('<syntaxhighlight')) {  $closingTag =  '</syntaxhighlight>' }
                elseif($line.Contains('{| class="wikitable" ')) { 
                    $closingTag =  '|}' 
                    $isWikiTableInProgress = $true
               }
                While($line -ne $Null -and -not $line.Contains($closingTag) -and ($ctr -lt $result.Count)) {
                    if($isWikiTableInProgress) {
                        $result[$ctr] = $result[$ctr].TrimStart(' ')
                    }
                    $ctr++
                    $line = $result[$ctr]
                }
                $codeBlockStart = -1
                $isWikiTableInProgress = $false
            }
            ElseIf(isLineMediaWikiCodeBlock $line) {
                if($codeBlockStart -eq -1) {
                    $codeBlockStart = $ctr
                }
            }
            Else{
                if($line.StartsWith(' ')) { # it starts with space but does not qualify for code block
                    $result[$ctr]  = $result[$ctr].TrimStart()
                }

                $result[$ctr] = $result[$ctr] -replace '<br/>|<br />|<br>', "" #<br> tag causing issues while rendering changing it to \n also has its own set of problems

                #enclose everything detected above as code in a asingle code block else pandock createsa anew clock of each line
                $idx = $ctr-1
                $result = createCodeBlock -lineArr $result -codeBlockStart $codeBlockStart -codeBlockEnd  $idx
                $codeBlockStart = -1
            }

            If($line) {
                
                # fixing some common pandoc errors
                If($line.StartsWith(':')) {
                     $result[$ctr] = $result[$ctr].TrimStart(':') #remove ':' as pandoc is unable to understand it
                     $result[$ctr] = $result[$ctr].TrimStart(' ')

                }
                If($line.Contains('{{table}}')) {
                    $result[$ctr] = $result[$ctr] -replace '{{table}}\s*\||{{table}}', ''
                }
                If($line.Contains('|-|}') ) {
                    $result[$ctr] = $result[$ctr] -replace '|}', ''
                }
                
            }
        }

    }

    $idx = $ctr-1

    $result = createCodeBlock -lineArr $result -codeBlockStart $codeBlockStart -codeBlockEnd $idx
    $codeBlockStart = -1
    
    $newContent = $result -join "`n"

    return $newContent
}

function createCodeBlock($lineArr, $codeBlockStart, $codeBlockEnd) {

    If($codeBlockStart -ne -1) {
        if($codeBlockStart -eq ($codeBlockEnd)) {
            if($lineArr[$codeBlockEnd].Trim(' ') -ne '') {
                $lineArr[$codeBlockEnd] = '<pre>' + $lineArr[$codeBlockEnd] + '</pre>'
            }
        }
        Else {
            $lineArr[$codeBlockStart] = '<pre>' + $lineArr[$codeBlockStart]
            $lineArr[$codeBlockEnd] = $lineArr[$codeBlockEnd] + '</pre>'
        }
        $codeBlockStart = -1
    }

    return $lineArr
}

function preProcessTemplateContent($content) {
    # remove noinclude tag with its content
    $content = $content -replace '<noinclude>((.|\n)*?)<\/noinclude>',''
    # remove inludeonlytag but retain content
    $content = $content -replace '<includeonly>((.|\n)*?)<\/includeonly>','$1'

    # for tempaltes, let links not have pipesymbol
    $content = $content -replace '\[\[(.*?)\|(.*?)\]\]','[[$1]]' 
    # encode parameter syntax so that pandoc ignores it
    $content = $content -replace '{{{((.|\n)*?)}}}','%7B%7B%7B$1%7D%7D%7D'

    return $content
    
}

if($pageName) {
    preProcessPage -path $pagePath -pageName $pageName
} elseif($templateName) {
    preprocessTemplate -path $templatePath -pageName $templateName
}