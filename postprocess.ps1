param(
    [string]$pageName, 
    [string]$pagePath, 
    [string]$templateName,
    [string]$templatePath,
    [string]$mediawikiDomain,
    $allPagesPathMap, 
    $allTemplatesPathMap,
    $renamedTempalteArr,
    [string]$localMachinePath,
    [string]$originalmMediaWikiUrl
)

$variablesPath  = $PSScriptRoot + '\.\Variables.ps1'
. $variablesPath

function postProcessPage($path) {
    $content = Get-Content $path -Raw
    $content = postProcessPageContent $content
    Set-Content -Path $path -Value $content
}

function postProcessTemplate($path) {
    $content = Get-Content $path -Raw
    $content = postProcessPageContent $content
    $content = postProcessTemplateContent $content
    Set-Content -Path $path -Value $content
}

function postProcessTemplateContent($content) {
    $content = $content -replace '%7B%7B%7B((.|\n)*?)%7D%7D%7D','{{{$1}}}'
    $content = $content -replace '{{{(.*?)\|(.*?)}}}','{{{$1|"$2"}}}'
    return $content
}

function postProcessPageContent($content) {
    # remove force toc tag
    $content = $content -replace '\\_\\_TOC\\_\\_', ''
    $content = convertImagesForCurrentPage $content
    $content = addFootercontent $content 
    $content = convertUrlsForCurrentPage $content
    $content = handleUNCPath $content 
    $content = fixTempalteSymbol $content

    return $content
}

function convertImagesForCurrentPage($content) {
    # replace image content with new paths
    # inline-style 
    # what if it is an absolute path : media wiki seems to not support absolute image paths
    # what about extension : already present
    $content = $content -replace '(!\[)(.*?)(\])(\()([^\s]*?)(\))', '![$2]($5 "")' #change all urls to a astandard format
    $content = $content -replace'(!\[)(.*?)(\])(\()((?!https|http).*?)(\s)(\".*?\")(\))', '![$2](.attachments\$5$6$7)' #change that standard format to correct path - ignore absolute apths

    return $content
}

function convertUrlsForCurrentPage($content) {
    
    #absolute urls are handled before external so that any absolute url pointing to the current mediawiki is changed to relative url instead
    $content = convertAbsoluteMediWikiUrl $content
    $content = convertExtenralUrl $content 
    $content = convertWikiLinks -content $content

    return $content
}

#changes any absolute url pointing to our mediawiki to a mediawiki format url
function convertAbsoluteMediWikiUrl($content) {
    # inline-style 
    # [](..."wikilinks")  
    $regexUrl = '<'+$originalmMediaWikiUrl + '([^\>]*)>' 
    $content = $content -replace $regexUrl, '[$1]($1"wikilink")'
    
    $regexUrl = '(\[)([^\]]*)(\])\('+ $originalmMediaWikiUrl + '([^\)]*)\)' 
    $content = $content -replace $regexUrl, '[$2]($4"wikilink")'

    return $content
}

function replaceSlash($url)
{
    $url = $url -replace '\\', '/'
   # $url = $url -replace '\/\(', '\('
   # $url = $url -replace '/\)', '\)'

    return $url 
}

function fixEncoding($url)
{
    return reverseReplaceSpecialCharacters $url
}

function reverseReplaceSpecialCharacters($pathName) {

    #Encoded
    $pathName = $pathName.Replace('%3A',':')
    $pathName = $pathName.Replace('%3E','>')
    #$pathName = $pathName.Replace('-','%2D')
    $pathName = $pathName.Replace('%3C','<')
    $pathName = $pathName.Replace('%7C','|')
    $pathName = $pathName.Replace('%3F','?')
    $pathName = $pathName.Replace('%22','"')
    $pathName = $pathName.Replace('%2A','*')
    #$pathName = $pathName.Replace('\', '%5C') #vaaror - added new make sure actual path characters are not changed - this is only for file names
    return $pathName
}

function FixLinkFormat($url)
{
    #trim all but one leading slash
    $url = $url.Trim('\')
    $url = '\' + $url

    $urlSection = $url -split '#'

    $urlSection[0] = replaceSlash $urlSection[0]
    $urlSection[0] = fixEncoding $urlSection[0]
    
    $url = $urlSection[0]
    if($urlSection.Length -gt 1)
    {
        $url = $url + '#' + $urlSection[1]
    }

    return $url
}

function convertWikiLinks($content) {
    $parts = $content -split '(\[)([^\]]*)(\])(\()(((?!wikilink|\[|https:\/\/|http:\/\/).)*)"wikilink"(\))'

    $pos = 0
    $nextMatchingPos = -1
    $nextIgnoredGroup = -1
    $nextMatchingLinkTextPos = -1
    $newContent = ''

    while($pos -lt $parts.Length) {

        if($pos -eq $nextMatchingPos) {
            # only format the page name and not the section name
            $currentNameArr = $parts[$pos] -split '#'
           
            $currentName = $currentNameArr[0]
             

            $currentName = $currentName.Trim()
            $currentName = $currentName.TrimStart(':')
            $currentName = replaceUnderscoreInPageName -pageName $currentName
            $currentName = $currentName -replace '\\\(', '('
            $currentName = $currentName -replace '\\\)', ')'

            $currentName = $currentName -replace '\\\\', '%5C'

            # removign any spaces between 'Category:' and <<category name>>
            If($currentName.StartsWith($mediaWikiCategoryPrefix)) {
              $currentName = $currentName.Remove(0, $mediaWikiCategoryPrefix.Length);
              $currentName = $currentName.TrimStart();
              $currentName = $mediaWikiCategoryPrefix + $currentName
            }

            If($allPagesPathMap.ContainsKey($currentName) -or $allPagesPathMap.ContainsKey($mediaWikiCategoryPrefix + $currentName)) {
                $newPath = $allPagesPathMap[$currentName]
                If($newPath -eq $null) {
                    $newPath = $allPagesPathMap[$mediaWikiCategoryPrefix + $currentName]
                }

                If($newPath.StartsWith($localMachinePath)) {
                    $wikiPath = $newPath.subString($localMachinePath.Length, $newPath.Length - $localMachinePath.Length - 3)
                    $wikiPath = FixLinkFormat $wikiPath

                   
                    $parts[$pos] = $wikiPath #formatPageNameInLinks $parts[$pos]
                    $parts[$pos] = $parts[$pos] -replace '\(', '\(' # escape the characters in name
                    $parts[$pos] = $parts[$pos] -replace '\)', '\)'
                }
            }
            Else {
                $parts[$pos] =  formatPageName $currentName
            }

            If($currentNameArr.Length -gt 1) {
                $parts[$pos] = $parts[$pos] + "#" + $currentNameArr[1].Replace('_', '-')
            }
           
        }
        ElseIf($pos -eq $nextMatchingLinkTextPos) {
            If($parts[$pos].StartsWith($mediaWikiCategoryPrefix)) {
                $parts[$pos] = $parts[$pos].Remove(0, $mediaWikiCategoryPrefix.Length)
            }
        }


        # Look for next occurance of [
        if($parts[$pos] -eq "[") {
            $nextMatchingPos = $pos + 4
            $nextIgnoredGroup = $pos + 5
            $nextMatchingLinkTextPos = $pos + 1
        }
    

        if($pos -ne $nextIgnoredGroup) {
            $newContent = $newContent +  $parts[$pos]
        }
        $pos++
    }

    return $newContent
}

function convertExtenralUrl($content) {

    # in preprocess we encoded the url (as pandoc throws for a lot of characters) decode and get it back to normal
    $splitArr = $content -split '(\[)(.*?)(\])(\(https:\/\/)(.*?)(\))'
    $newContent = ''
    $indexToModify = 5
    While($indexToModify -lt $splitArr.Count) {
        $splitArr[$indexToModify] = decodeUrls $splitArr[$indexToModify]
        $indexToModify = $indexToModify + 7 # based on regex

    }
    $newContent = $splitArr -join ''
    # convert unchanged external links
    $splitArr = $newContent -split '(\[https:\/\/)(.*?)(\s)(.*?)(\])'
    $newContent = ''
    $indexToModify = 2
    While($indexToModify -lt $splitArr.Count) {

        If(-Not $splitArr[$indexToModify].StartsWith($mediawikiDomain)) { #vaaror: todo : see why this check was added
            $splitArr[$indexToModify] = decodeUrls $splitArr[$indexToModify]
        
        } 
        $indexToModify = $indexToModify + 6        
    }
    $newContent = $splitArr -join ''

    #convert urls converted to <a href="..."
    $splitArr = $newContent -split '(\<a href=\")(.*?)(\")(.*?)(\>)'
    $newContent = ''
    $indexToModify = 2
    While($indexToModify -lt $splitArr.Count) {

        If(-Not $splitArr[$indexToModify].StartsWith($mediawikiDomain)) {
            $splitArr[$indexToModify] = decodeUrls $splitArr[$indexToModify]

        } 
        $indexToModify = $indexToModify + 6
    }
    $newContent = $splitArr -join ''

    return $newContent
}

function decodeUrls($urlContent) {
    $urlContent = $urlContent -replace '%5C%28', '\(' # url decode handle this
    $urlContent = $urlContent -replace '%5C%29', '\)' # url decode handle this
    $urlContent = [System.Net.WebUtility]::UrlDecode($urlContent)

    return $urlContent
}

function handleUNCPath($content) {
    return $content -replace "(<file>)(.+?)(</file>)",'**$2**'
}

function addFootercontent($content) {
    #remove Hierarchy Top
    $content =  $content -replace '\[Category\:Hierarchy Top\]\(Category\:Hierarchy_Top(.*?)\)',''
    # read the content line by line backward
    $arr = $content -split "`n"
    [array]::Reverse($arr)
    $foundLastLineIdx = -1
    $i = 0
    While($foundLastLineIdx -eq -1 -and $i -lt $arr.Count) {
        $line = $arr[$i]
        If($line -ne $null -and $line.Trim() -ne '') {
            $foundLastLineIdx = $i
        }

        $i++
    }
     
    If($foundLastLineIdx -ne -1) {
        # if last line is parent category link - change
        If($line -match '((^(\[Category:)|(\[:Category:))(.*)(\]))') {
            $line = $arr[$foundLastLineIdx]
            $arr = [System.Collections.ArrayList]$arr
            $arr.RemoveAt($foundLastLineIdx)
            $newArr = @("---", " ", $line, " ", "---")
            $arr = $newArr + $arr
        }

    }
    [array]::Reverse($arr)

    $content = $arr -join "`n"
    return $content
}

# move to the vsts wiki tempalte syntax
function fixTempalteSymbol($content) {
    
    #convert {{PAGENAME}} to a parameter instead of tempalte name
    $pageNameRegex = '{{\(\s*' + $mediaWikiPageNameKeyword + '\s*\)}}'
    $pageNameParameterSyntax = '{{{'+ $mediaWikiPageNameKeyword + '}}}'

    $content = $content -replace $pageNameRegex, $pageNameParameterSyntax

    # all other templates
    $regexArr = $content -split '{{\(((.|\n)*?)\)}}'
    $newContent = ''
    $nextIdxToProcess = 1
    $nextIdxToskip = 2
    $idx = 0

    While($idx -lt $regexArr.Length) {
        if($idx -eq $nextIdxToProcess) {
            ## Tempalte content
            $templateCall = $regexArr[$idx]
            
            $params = $templateCall -split '\|'
            $params[0] = $params[0].Trim([Environment]::NewLine)
            $params[0] = $params[0].Trim(' ')
            
            $fullTempalteName = $params[0]

            $fullTempalteName = $fullTempalteName -replace '\\_',' '

            # fix the template name only if we identify it
            if($allTemplatesPathMap.ContainsKey($fullTempalteName)) {
                $diskName = ($allTemplatesPathMap[$fullTempalteName] -split '.templates\\')[1]
                $params[0] = $diskName
            } elseif($renamedTempalteArr.ContainsKey($fullTempalteName)){
                $redirectedName = $renamedTempalteArr[$fullTempalteName]
                $diskName = ($allTemplatesPathMap[$redirectedName] -split '.templates\\')[1]
                $params[0] = $diskName
            }

            $params[0] = $params[0].TrimStart(' ')
            # remove template prefix from name
            if($params[0].StartsWith($mediaWikiTemplatePrefix)) {
                $params[0] = $params[0].Remove(0, $mediaWikiTemplatePrefix.Length)
            }
            $params[0] = $params[0].TrimStart(' ')
            $params[0] = $params[0] + "`n"
            $newSyntaxTemplateContent = $params[0] + "`n" # vaaror: why this extra newline

            # first param was template name, subsequent ones are template parameters
            for($i = 1; $i -lt $params.Count; $i = $i + 1) {
                $newParam = @() 
                # key = value
                $newParam = $params[$i] -split '='
                if($newParam.Count -gt 2) {

                    for($j=2;$j -lt $newParam.Count; $j++) {
                        $newParam[1] =  $newParam[1] + '='+ $newParam[$j]
                        $newParam[$j] = ''
                    }
                    $newParam = $newParam[0..1]

                }

                if($newParam.Count -eq 2) {
                    $newParam[1] = $newParam[1] -replace '\"','\"'
                    $newParam[1] = '"' + $newParam[1] + '"' 
                } elseif($newParam.Count -eq 1) {
                    $newParam[0] = $newParam[0] -replace '\"','\"'
                     $newParam[0] = '"' + $newParam[0] + '"' 
                }

                $params[$i] = $newParam -join ':' # replace '=' with ':'
                $newSyntaxTemplateContent = $newSyntaxTemplateContent + $params[$i] + ',' # replace '|' with ','
            }
            $newSyntaxTemplateContent = $newSyntaxTemplateContent.TrimEnd(',')
            $newSyntaxTemplateContent = $newSyntaxTemplateContent + "`n"

            $templateCall = "`n`n" + $vstsWikiTemplatesPathSyntax + $newSyntaxTemplateContent + "`n:::`n"
            $regexArr[$idx] =  $templateCall
            $nextIdxToProcess = $nextIdxToProcess + 3
        }

        if($idx -eq $nextIdxToskip) {
            $nextIdxToskip = $nextIdxToskip + 3
        } else {
            $newContent = $newContent + $regexArr[$idx] 
        }

        $idx = $idx + 1
    }

   return $newContent 
}

if($pageName) {
    postProcessPage -path $pagePath -pageName $pageName
} elseif($templateName) {
    postProcessTemplate -path $templatePath -pageName $templateName
}