param(
    [Parameter(Mandatory=$True, HelpMessage="Your media wiki url for which credentails are provided/open wiki <format: http://localhost:8080/mediawiki>")]
    [string]$mediWikiUrl, 
    [Parameter(Mandatory=$True, HelpMessage="Your image backup location <format: C:\xampp\htdocs\mediawiki\images>")]
    [string]$imageDiskPath, 
    [Parameter(Mandatory=$True, HelpMessage="mediawiki username <format: alias>" )]
    [string]$u,
    [Parameter(Mandatory=$True, HelpMessage="mediawiki password")]
    [SecureString]$p,
    [Parameter(Mandatory=$True, HelpMessage="output directory on disk <format: C:\anylocation\>")]
    [string]$o,
    [Parameter(Mandatory=$True, HelpMessage="vsts wiki clone url <format: https://myacct.visualstudio.com/proj/_git/proj.wiki>")]
    [string]$vstsWikiRemoteUrl,
    [Parameter(Mandatory=$True, HelpMessage="path where pandoc.exe resides <format: C:\pandoc\>")]
    [string]$pandocPath,
    [Parameter(Mandatory=$False, HelpMessage="vsts username (Please provide PAT token when asked for password)")]
    [string]$vstsUserName = "username",
    [Parameter(Mandatory=$False, HelpMessage="mediawiki absolute url(can be different from mediawiki url provided above - to change absolute urls in content) <format: https://mywiki.com/index.php\?title=>")] 
    [string]$originalmMediaWikiUrl, 
    [Parameter(Mandatory=$False, HelpMessage="updated mailto string")]
    [string]$mailToOrg
    )

    $variablesPath  = $PSScriptRoot + '\.\Variables.ps1'
    . $variablesPath

#input
$mediaWikiCoreUrl = $mediWikiUrl + '/api.php?format=json&'
$mediaWikiImageBackupPath = $imageDiskPath

$userName = $u
$password = ConvertTo-SecureString $pwd -AsPlainText -Force

$wikiName = $vstsWikiRemoteUrl|split-path -leaf
$rootPath = $o
$localMachinePath = $o + $wikiName + '\'

$attachmentFolderPath = $localMachinePath + $attachmentFolderName + '\'

#local
$mediaWikiGetCategoryMembers=$mediaWikiCoreUrl + 'action=query&list=categorymembers&cmlimit=500&cmtitle='
$mediawikiDomain = $originalmMediaWikiUrl.Split('/')[2]

$mediaWikiAllCategoriesTitleArray =  New-Object System.Collections.Generic.List[System.Object]
$mediaWikiAllPagesTitleArray =  New-Object System.Collections.Generic.List[System.Object]
$mediaWikiPageNamesContainingSlash =  New-Object System.Collections.Generic.List[System.Object]
$emptyCategoryFiles = New-Object System.Collections.Generic.List[System.Object]
$nonTempaltesArr = New-Object System.Collections.Generic.List[System.Object]

$duplicatePageNames =  New-CHashtable
$categoryTreeHashTable =  New-CHashtable
$renamedItems =  New-CHashtable
$renamedTempalteArr =  @{}
$allPagesPathMap =  New-CHashtable
$allTemplatesPathMap = @{} #case insensitive
$uniqueNameashTable =  New-CHashtable
$donePaths = New-CHashtable

#------------------------------------------------------------------
#---------------------------General Methods------------------------------------
#------------------------------------------------------------------

function Get-WebSession()
{
    
    if($websession -eq $null)
    {
        Invoke-LogIn $userName $password
    }
    return $websession
}

function Invoke-Login($username, $password)
{
    $uri = $mediaWikiCoreUrl

    $body = @{}
    $body.action = 'login'
    $body.format = 'json'
    $body.lgname = $username
    $body.lgpassword = $password


    $object = Invoke-WebRequest $uri -Method Post -Body $body -SessionVariable global:websession
    $json = $object.Content
    $object = ConvertFrom-Json $json
    
    if($object.login.result -eq 'NeedToken')
    {
        $uri = $mediaWikiCoreUrl
        
        $body.action = 'login'
        $body.format = 'json'
        $body.lgname = $username
        $body.lgpassword = $password
        $body.lgtoken = $object.login.token

        $object = Invoke-WebRequest $uri -Method Post -Body $body -WebSession $global:websession
        $json = $object.Content
        $object = ConvertFrom-Json $json
    }
    if($object.login.result -ne 'Success')
    {
       # throw ('Login.result = ' + $object.login.result)
    }
}

function formatPageName($pageName) {
    $pageName = renameCategoryPages($pageName)
    $pageName = replaceSpecialCharacters($pageName)
    $pageName = replaceDisallowedCharacters($pageName)
    $pageName = replaceSpaceInPageName($pageName)

    $pageName = $pageName.Replace('\', '%5C')

    return $pageName
}

function renameCategoryPages($name) {
    If($name.StartsWith($mediaWikiCategoryPrefix)) {
        return $name.Remove(0, $mediaWikiCategoryPrefix.Length)
    }

    return $name
}

function replaceSpaceInPageName($pathName) {
    $pathName = $pathName.Replace(' ','-')

    return $pathName
}

function replaceUnderscoreInPageName($pageName) {
    $pageName = $pageName.Replace('_',' ') # varor : added : changed it to space and not hyphen

    return $pageName
}

function replaceSpecialCharacters($pathName) {

    #Encoded
    $pathName = $pathName.Replace(':','%3A')
    $pathName = $pathName.Replace('>','%3E')
    $pathName = $pathName.Replace('-','%2D')
    $pathName = $pathName.Replace('<','%3C')
    $pathName = $pathName.Replace('|','%7C')
    $pathName = $pathName.Replace('?','%3F')
    $pathName = $pathName.Replace('"','%22')
    $pathName = $pathName.Replace('*','%2A')
    $pathName = $pathName.Replace('\', '%5C') #vaaror - added new make sure actual path characters are not changed - this is only for file names
    return $pathName
}

function replaceDisallowedCharacters($pathName) {

    $pathName = $pathName.Replace('/','_')

    return $pathName
}

function reverseReplaceDisallowedCharacters($pathName) {

    $pathName = $pathName.Replace('_','/')

    return $pathName
}

#------------------------------------------------------------------
#---------------------------Hierarchy------------------------------------
#------------------------------------------------------------------

function FetchChildrenForCategory($category) {
    If($category.StartsWith($mediaWikiCategoryPrefix)) {
    
        $mediaWikiGetCategoryMembersFullUrl  = $mediaWikiGetCategoryMembers + $category.Replace('%5C','\')
        $res = Invoke-WebRequest -Uri $mediaWikiGetCategoryMembersFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json
        return $res.query.categorymembers
    }

    return @()
}

# given any category creates a child
function createTreeForCategory($root, $rootPath) {
    If($categoryTreeHashTable.ContainsKey($root)) {
    } Else {
        $categoryList =  New-Object System.Collections.Generic.List[System.Object]

        If($root.StartsWith($mediaWikiCategoryPrefix)) {
            $nextCategory = $root
        } Else {
            $nextCategory = $mediaWikiCategoryPrefix + $root
        }

        $categoryTreeHashTable.Add($nextCategory, $rootPath)
        $categoryList.Add($nextCategory)
        $currentIndex = 0

        Do {
                $childred = FetchChildrenForCategory($categoryList[$currentIndex])
                $currentPath = $categoryTreeHashTable[$categoryList[$currentIndex]]
                ForEach($child in $childred) {
                 
                    $fileName =  $child.title
                    
                    if( -not $categoryTreeHashTable.ContainsKey($fileName)) {
                        $newPath = $currentPath +  $separator +  $fileName.Replace('\','%5C') 
                        $categoryTreeHashTable.Add($fileName,  $newPath)
                        $categoryList.Add($fileName)
                    }
                }

                $currentIndex++

        } While($currentIndex -lt $categoryList.Count)
    }
}

function createCategoryTree() {
    If($rootCategory -ne '' ) {
        $rootPath = '.' + $separator +  $mediaWikiRootCategory +  $separator  
        createTreeForCategory -root $rootCategory -rootPath   $rootPath
    }
}

function createPageHierarchy() {
    # this is the main logic function 
    # it creates the basic page hierarchy
    # some more hierarchy changes happen after 

    createCategoryTree #populates categoryTreeHashTable- Anything not in this will be in flat hierarchy
    getAllCategories  #$mediaWikiAllCategoriesTitleArray
    getAllPages  #mediaWikiAllPagesTitleArray
    getAllTemplates 

    #now that all pages, categories, tempaltes are here form a tree
    getAllPagesNameAndHierarchy #allPagesPathMap
    getNonTemplatesUsedAsTemplates #pages used as tempaltes will be move to templates folder - get those 
}

function getNonTemplatesUsedAsTemplates() {
    ForEach($key in $allPagesPathMap.Keys) {
        
        $mediaWikiGetAllPageTemplate = $mediaWikiCoreUrl + '&action=query&titles='+$key + '&prop=templates&tllimit=500'
        $res = Invoke-WebRequest -Uri $mediaWikiGetAllPageTemplate | ConvertFrom-Json

        $templates =  $res.query.pages.psobject.properties.value.templates 
        if($templates) {
            forEach($template in $templates) {
                $name = $template.title

                if(-Not $name.StartsWith($mediaWikiTemplatePrefix) -and -Not $nonTempaltesArr.Contains($name)) {
                    $nonTempaltesArr.Add($name)
                }
            }
        }
    }

    Write-Host 'total count of non tempalte pages used as templates' $nonTempaltesArr.Count
    [System.Collections.ArrayList]$RemovalList = @()

    ForEach($item in $nonTempaltesArr) {

        if($allPagesPathMap.ContainsKey($item)) {

            $path = $allPagesPathMap[$item]
            $name = $path.Substring($path.LastIndexOf($separator)+1)

            #check if tempalte with name TEmplate: <$item> does not already exisit
            $potentialTemplateName = $mediaWikiTemplatePrefix + $item

            if($allTemplatesPathMap.ContainsKey($potentialTemplateName)) {
                Write-Host 'Same name template already exists'$potentialTemplateName
                #rocky terrain - better to not move this tempalte
                $RemovalList.Add($item)
            }
            else {
                if($name.StartsWith($mediaWikiCategoryPrefix)) {
                    $name = $name.Remove(0,$mediaWikiCategoryPrefix.Length-1) # leave a trailing ':' to identify it as  a page
                }
                $newName = $localMachinePath + $vstsWikiTemplatesDiskPath +$name
            }
            $allTemplatesPathMap.Add($item, $newName)
        } 
    }

    foreach($item in $RemovalList){
        $nonTempaltesArr.Remove($item)
    }
}

function getAllPages() {
    do {
        $mediaWikiGetAllPagesFullUrl = $mediaWikiCoreUrl + $mediaWikiGetAllPagesPartialUrl + $mediaWikiAllPagesContinuationToken + '=' + $mediaWikiAllPagesContinuationTokenValue
        
        $res = Invoke-WebRequest -Uri $mediaWikiGetAllPagesFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json

        If($res.query) {          
            if($res.continue) {
                $mediaWikiAllPagesContinuationTokenValue = $res.continue.$mediaWikiAllPagesContinuationToken
            } else {
                $mediaWikiAllPagesContinuationTokenValue = ''
            }
            
            # add name to all category array
            ForEach($child in $res.query.allpages) {
                $title = $child.title.Trim('\"')
                
                if($uniqueNameashTable.ContainsKey($title.ToLower())) {
                    # if a file with this name already exists - dont process
                    $duplicatePageNames.Add($title, $uniqueNameashTable[$title.ToLower()]) #TODO do this for categories as well
                } else {
                    $uniqueNameashTable.Add($title.ToLower(), $title)
                    $mediaWikiAllPagesTitleArray.Add($title)
                }                
            }
        }
    } while ($mediaWikiAllPagesContinuationTokenValue -ne '')


    $mediaWikiAllPagesTitleArray.ToArray();
}


# merges  normal pages and category pages and creates $allPagesPathMap
function getAllPagesNameAndHierarchy() {
    $allItems = $mediaWikiAllPagesTitleArray + $mediaWikiAllCategoriesTitleArray
    ForEach($item in $allItems) {
        $urlencodedPageName = formatPageName $item
        $relativePath = $separator 
        If($categoryTreeHashTable.ContainsKey($item)) {
            $pathArr = $categoryTreeHashTable[$item] -split '\\'

            for($i = 0; $i -lt $pathArr.Count - 1; $i++) {
                If($pathArr[$i] -eq '.') {
                    Continue
                }
               $formattedName =  formatPageName $pathArr[$i] 
               $relativePath = $relativePath + $formattedName + $separator 
            }          
        }

        # move all unparented the pages to this hierarchy by default
        If($relativePath -eq $separator  ) {
                $relativePath = '\Orphaned-pages\'
       }

        $relativePath  = $relativePath -replace '\\Hierarchy\%2DTop\\','\' #hardoded here for regex escaping
        $fileName = $localMachinePath + $relativePath + $urlencodedPageName + ".md"

        $allPagesPathMap.Add($item, $fileName)  
    }
}

function getAllCategories() {
    # Get all categories
    do {
        $mediaWikiGetAllCatgoriesFullUrl = $mediaWikiCoreUrl + $mediaWikiGetAllCatgoriesPartialUrl + $mediaWikiAllCategoriesContinuationToken + '=' + $mediaWikiAllCategoriesContinuationTokenValue
        $res = Invoke-WebRequest -Uri $mediaWikiGetAllCatgoriesFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json
        
        If($res.query) {
            # new continuation token
            if($res.continue) {
                $mediaWikiAllCategoriesContinuationTokenValue = $res.continue.$mediaWikiAllCategoriesContinuationToken
            } else {
                $mediaWikiAllCategoriesContinuationTokenValue = ''
            }
            # add name to all category array
            ForEach($child in $res.query.allcategories) {
                $title = $child.psobject.properties.value
                $fulltitle = $mediaWikiCategoryPrefix + $title
                $rootPath = '.\' + $orphanedPagesFolder + $separator + $title
                createTreeForCategory -root $fulltitle -rootPath $rootPath
                $mediaWikiAllCategoriesTitleArray.Add($fulltitle)
            }
        }
    } while ($mediaWikiAllCategoriesContinuationTokenValue -ne '')
    
    $mediaWikiAllCategoriesTitleArray.ToArray();
}

function getAllTemplates() {
    $mediaWikiAllTemplatesContinuationTokenValue = ''
    # Get all templates
    do {
        $mediaWikiGetAllTemplatesFullUrl = $mediaWikiCoreUrl + $mediaWikiGetAllPagesPartialUrl + $mediaWikiAllPagesContinuationToken + '=' + $mediaWikiAllTemplatesContinuationTokenValue + '&apnamespace=10'
        
        $res = Invoke-WebRequest -Uri $mediaWikiGetAllTemplatesFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json

        If($res.query) {
            # new continuation token        
            if($res.continue) {
                $mediaWikiAllTemplatesContinuationTokenValue = $res.continue.$mediaWikiAllPagesContinuationToken
            } else {
                $mediaWikiAllTemplatesContinuationTokenValue = ''
            }
            
            # add name to all category array
            ForEach($child in $res.query.allpages) {
                $title = $child.title.Trim('\"')
                $prunedTitle = $title.Remove(0, $mediaWikiTemplatePrefix.Length)
                $formattedName = formatPageName $prunedTitle
                $path = $localMachinePath + $vstsWikiTemplatesDiskPath + $formattedName + '.md'
                $allTemplatesPathMap[$title] = $path
            }
        }
    } while ($mediaWikiAllTemplatesContinuationTokenValue)
}

#------------------------------------------------------------------
#------------------- Page Content----------------------------------
#------------------------------------------------------------------

function getContent() {
    getTempaltecontent
    getPageContent
    handleSpecialPages
}

function getCurrentPage ($itemOriginalName) {
    $mediaWikiPageContentFullUrl = $mediaWikiCoreUrl + $mediaWikiPageContentPartialUrl + $itemOriginalName
    $res = Invoke-WebRequest -Uri $mediaWikiPageContentFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json
    $isMissing = $res.query.pages.psobject.properties.value.missing -eq ''
    $content = ''

    if(-Not $isMissing) {
        $content = $res.query.pages.psobject.properties.value.revisions[0].'*'
    }
    
    return $content
}

function getPageContent() {
    
    $currentCount = 1
    $totalCount = $allPagesPathMap.Count

    Foreach ($key in @($allPagesPathMap.Keys)) {

        $path = $allPagesPathMap[$key]
        $itemOriginalName = $key

        Write-Host '****************************************************************************'
        Write-Host 'Fetching ' $currentCount ' of ' $totalCount ': ' $itemOriginalName '| Final name: ' $path
        $currentCount++
        $content = ''
        $content = getCurrentPage $itemOriginalName 
        If(-Not $itemOriginalName.StartsWith($mediaWikiCategoryPrefix)) {
            If($content -eq $null -or $content.Trim(' ') -eq '') {
                #dont create this file
                $allPagesPathMap.Remove($key)

            }
            #for non-category items, remove redirect only links
            ElseIf(isRedirectPage $content) {
                $renamedName = getRenameName $content
                $renamedItems.Add($itemOriginalName, $renamedName)
                $allPagesPathMap.Remove($key) # pick this from renamed list only to avoid confusion
            }
            Else {
                createPage -path $path -content $content
            }
        }
        Else {
                
                if($content -eq $null) {
                    $content = ''
                }
                $isEmpty = isEmptyCategoryFile $content
                If($isEmpty -eq $true) {
                    $emptyCategoryFiles.Add($key)
                }
                # no matter what : create the category
                createPage -path $path -content $content
        }
    }

    Write-Host '#####################################################'

    Write-Host 'FINISHED WITH '$allPagesPathMap.Count
}

function getTempaltecontent() {
    Foreach ($key in $allTemplatesPathMap.Keys) {
        
        $path = $allTemplatesPathMap[$key]
        $content = getCurrentPage $key 
        #if it is a redirect only page, do not create the page, instead save separately
        if($content) {
            if(isRedirectPage $content){ 
                $renamedName = getRenameName $content
                $renamedTempalteArr.Add($key, $renamedName)
            } else {
                createPage -path $path -content $content
            }
        }
    }

    #remove renamed items from main arr
    foreach($key in $renamedTempalteArr.Keys) {
        $allTemplatesPathMap.Remove($key)
    }
}

function getRenameName($content) {
    If(isRedirectPage $content) {
         #if content starts with REDIRECT ignore it
         $renamedPathArr = $content -split $renamedPageRegEx
         $renamedName  = $renamedPathArr[1].TrimStart(':').Replace('_',' ')

         return $renamedName
    }
    
    return ''
}

# empty category file is different from empty file. 
# for parent, file containg jsut parent link is also considered empty
function isEmptyCategoryFile($content) {
    $isContentPresent = $false
    $isParentCategoryLinkFound = $false

    $lines = $content -split "`n"

    ForEach($line in $lines) {
        If($isContentPresent -eq $false) {
            If($line.Trim(' ') -ne '') {
                $isThisParentCategoryLink = isParentCategoryLink $line -or isRedirectPage $line 
                If(-Not $isParentCategoryLinkFound -and $isThisParentCategoryLink ) {
                    $isParentCategoryLinkFound = $true
                }
                Else {
                    $isContentPresent = $true
                }           
            }
        }
    }

    return $isContentPresent -eq $false
}

function isRedirectPage($content) {
    return $content.TrimStart(' ').StartsWith('#REDIRECT', "CurrentCultureIgnoreCase")
}

function isParentCategoryLink($line) {
    return $line -match '((^(\[\[Category:)|(\[\[:Category:))(.*)(\]\]))'
}

function createPage($path, $content) {
    New-Item -ItemType file -Force -Path $path
    [System.IO.File]::WriteAllLines($path, $content)
}

#------------------------------------------------------------------
#---------------------------Special Files--------------------------
#------------------------------------------------------------------

# Duplicate page names - TODO handle categories as well here
function handleSpecialPages() {
    
    ForEach($pageWithDuplicateName in $duplicatePageNames.Keys) {
        $content = getCurrentPage $pageWithDuplicateName, $Header
        $isRedirectOnlyPage = isRedirectPage $content
        If($content -eq $null -or $content.Trim(' ') -eq '') {
            $renamedItems.Add($pageWithDuplicateName, $null)
        }  ElseIf(-Not $pageWithDuplicateName.StartsWith($mediaWikiCategoryPrefix) -and $isRedirectOnlyPage) {
            $renamedName  = getRenameName $content
            $renamedItems.Add($pageWithDuplicateName, $renamedName)
        }
        Else {
        
            If($allPagesPathMap.ContainsKey($duplicatePageNames[$pageWithDuplicateName])) {
                $fullpath = $allPagesPathMap[$duplicatePageNames[$pageWithDuplicateName]]

                $newFilePath = getAlternateFilePath $fullpath
                $allPagesPathMap[$pageWithDuplicateName] = $newFilePath

                createPage -path $newFilePath -content $content
            }            
        }
    }

    PreprocessRenamedArray
}

# appends counter to original name if it already exists
function getAlternateFilePath($pathName) {
    
    $counter = 1
    $newPathName = [System.IO.Path]::GetDirectoryName($pathName)
    $newFileName = [System.IO.Path]::GetFileNameWithoutExtension($pathName)
    $fullPath = $pathName
    while(Test-Path $fullPath) {
        $counter++
        $fullPath = $newPathName +"\" + $newFileName + '(' + $counter + ')' + '.md'
    }

    return $fullPath
}

# renamed arry coud be like
# A-> B
# B- > C
# C- > D
# simplify this to 
# A-> D
# B-> D
# C-> D
function PreprocessRenamedArray() {
    $renamedItems = PreprocessRenamedArrayInternal -renamedMap $renamedItems

    #copy relavant renamed items to original array
    ForEach ($key in $renamedItems.Keys) {
        $val = $renamedItems[$key]
        If($val) {
            $val = $val.Trim()
            If(-Not $allPagesPathMap.ContainsKey($key) -and $allPagesPathMap.ContainsKey($val)) {
                $allPagesPathMap[$key] = $allPagesPathMap[$val]
            }
        }
    }

    $renamedTempalteArr = PreprocessRenamedArrayInternal -renamedMap $renamedTempalteArr

    #copy relavant renamed items to original array
    ForEach ($key in $renamedTempalteArr.Keys) {
        $val = $renamedTempalteArr[$key]
        If($val) {
            $val = $val.Trim()
            If(-Not $allTemplatesPathMap.ContainsKey($key)) {
                If (-Not $allTemplatesPathMap.ContainsKey($val) ){
                
                # Additional logic for templates as normal moved pages can also be tempaltes
                    Write-Host 'Just one try to find if renamed page was also renamed' 
                    if($allPagesPathMap.ContainsKey($val)) {
                        $path = $allPagesPathMap[$val]
                        $name = $path.Substring($path.LastIndexOf($separator)+1)
                        $newName = $localMachinePath + $vstsWikiTemplatesDiskPath + $name

                        $allTemplatesPathMap.Add($val, $newName)
                        if(-Not $nonTempaltesArr.Contains($val)) {
                            $nonTempaltesArr.Add($val)
                        }
                    }
                }
                Else {
                    $allTemplatesPathMap[$key] = $allTemplatesPathMap[$val]
                }
            }
        }
    }
}

function PreprocessRenamedArrayInternal($renamedMap) {
    ForEach ($key in @($renamedMap.Keys)) {
        $val = $renamedMap[$key]

        while($val -ne $null) {
            
            If($renamedMap.ContainsKey($val)) { # todo check if this is case sensitive
                If($val -ceq $renamedMap[$val]) {
                    $val = $null
                }
                Else {
                    $renamedMap[$key] = $renamedMap[$val]
                    $val = $renamedMap[$val]
                }
            }
            Else {
                $val = $null
            }
        }
    }
    
    return $renamedMap
}

#------------------------------------------------------------------
#-----------------------Processing--------------------------------
#------------------------------------------------------------------
function processPage($path) {
    $pandocCommand = $pandocPath + 'pandoc.exe' 
    & $pandocCommand  $path --from=mediawiki --to=gfm  -o $path --eol=native --wrap=preserve
}

function processTemplate($path) {
    processPage $path
}

#------------------------------------------------------------------
#---------------------------Content Migration----------------------
#------------------------------------------------------------------

# migrates single page
function migratePage($path, $pageName) {

    # why we read write the file content again and again instead of single read in the beginnign and write at the end
    # pandoc (used in processPage step) does not take in raw content instead takes the file path to read and write
    Write-Host 'preprocessing '$path 'file: '$pageName
    $preprocessScriptPath = $PSScriptRoot + '\.\preProcess.ps1'
    & $preprocessScriptPath -pagePath $path -pageName $pageName -mediawikiDomain $mediawikiDomain

    Write-Host 'processing '$path 'file: '$pageNam
    processPage $path

    Write-Host 'postprocessing '$path 'file: '$pageNam
    $postprocessScriptPath = $PSScriptRoot + '\.\postProcess.ps1'
    & $postprocessScriptPath -pagePath $path -pageName $pageName -allPagesPathMap $allPagesPathMap -allTemplatesPathMap $allTemplatesPathMap -renamedTempalteArr $renamedTempalteArr -localMachinePath $localMachinePath -originalmMediaWikiUrl $originalmMediaWikiUrl -mediawikiDomain $mediawikiDomain
    

}

function migrateTemplate($content, $pageName) {
    Write-Host 'preprocessing '$path ' template : '$pageName
    $preprocessScriptPath = $PSScriptRoot + '\.\preProcess.ps1'
    & $preprocessScriptPath -templatePath $path -templateName $pageName -mediawikiDomain $mediawikiDomain

    Write-Host 'processing '$path ' template : '$pageName
    processTemplate $path

    Write-Host 'postprocessing '$path ' template : '$pageName
    $postprocessScriptPath = $PSScriptRoot + '\.\postProcess.ps1'
    & $postprocessScriptPath -templatePath $path -templateName $pageName -mediawikiDomain $mediawikiDomain -allPagesPathMap $allPagesPathMap -allTemplatesPathMap $allTemplatesPathMap -renamedTempalteArr $renamedTempalteArr -localMachinePath $localMachinePath -originalmMediaWikiUrl $originalmMediaWikiUrl
}

#------------------------------------------------------------------
#---------------------------Git------------------------------------
#------------------------------------------------------------------

function getGitUrlWithCreadentials() {
    if($vstsWikiRemoteUrl.StartsWith('http://')) {
        $splitToken = 'http://'
    } else {
        $splitToken = 'https://'
    }

    $urlArr = $vstsWikiRemoteUrl -split $splitToken
    $url = $splitToken + $vstsUserName + '@' + $urlArr[1]
    return $url
}

function initializeGit() {
    Set-Location $rootPath
    $url = getGitUrlWithCreadentials
    git clone $url -v
    git pull
    Set-Location $wikiName
    git checkout wikiMaster
}

function pushVSTSWiki() {
    git add .
    git commit -m mediWiki
    git push -f

}

#------------------------------------------------------------------
#
#------------------------------------------------------------------

# CODE DUPLICATION ALERT
function remveFooterContent($content) {
    $arr = $content -split "`n"
    [array]::Reverse($arr)
    $foundLastLineIdx = -1
    $i = 0
    While($foundLastLineIdx -eq -1 -and $i -lt $arr.Count) {
        $line = $arr[$i]
        If($line -and $line.Trim() -ne '') {
            $foundLastLineIdx = $i
        }
        $i++
    }

    If($foundLastLineIdx -ne -1) {
        $line = $arr[$foundLastLineIdx]
        if($line.Trim() -eq '---') {
            if($arr.Count -gt $foundLastLineIdx + 4) { # if there is space for --- \n <content>\n ---
                if($arr[$foundLastLineIdx+1].TrimEnd() -eq '' -and $arr[$foundLastLineIdx+3].TrimEnd() -eq '' -and $arr[$foundLastLineIdx+2] ) {
                    $idx = $foundLastLineIdx+5
                    $arr = $arr[$idx..($arr.Length-1)]
                }
            }
            
        }
    } 

    [array]::Reverse($arr)

    $content = $arr -join "`n"
    return $content
}

# CODE DUPLICATION ALERT
function getFooterContent($content) {
    $arr = $content -split "`n"
    [array]::Reverse($arr)
    $foundLastLineIdx = -1
    $i = 0
    $footerContent = ''
    While($foundLastLineIdx -eq -1 -and $i -lt $arr.Count) {
        $line = $arr[$i]
        If($line -ne $null -and $line.Trim() -ne '') {
            $foundLastLineIdx = $i
        }

        $i++
    }

    If($foundLastLineIdx -ne -1) {
        $line = $arr[$foundLastLineIdx]
        if($line.Trim() -eq '---') {
            if($arr.Count -gt $foundLastLineIdx + 4) { # if there is space for --- \n <content>\n ---
                if($arr[$foundLastLineIdx+1].TrimEnd() -eq '' -and $arr[$foundLastLineIdx+3].TrimEnd() -eq '' -and $arr[$foundLastLineIdx+2] ) {
                    $footerContent = $arr[$foundLastLineIdx+2]
                    
                }
            }
        }
    }

    if($footerContent) {
       $footerContent =  "`n---`n `n" + $footerContent + "`n `n---"
    }

    return $footerContent
}

function CopyPagesToTemplatesFolder() {
    foreach($item in $nonTempaltesArr) {
        Write-Host 'Copying item '$item 'from page to tempalte '$allPagesPathMap[$item] '  to '$allTemplatesPathMap[$item]
        if($allPagesPathMap.ContainsKey($item) -and $allPagesPathMap[$item]) {

            # copy file form $allPagesPathMap[$item] to $allTemplatesPathMap[$item]
            Copy-Item -Path $allPagesPathMap[$item] -Destination $allTemplatesPathMap[$item]

            $content = Get-Content $allTemplatesPathMap[$item] -Raw
            $content = remveFooterContent $content
            Set-Content -Path $allTemplatesPathMap[$item] -Value $content
        }
    }

    #this is a seaprate loop to handle multiple files pointing to a same fiel being refered as tempalte
    foreach($item in $nonTempaltesArr) {
        if($allPagesPathMap.ContainsKey($item)) {
            $oldPath = $allPagesPathMap[$item]
            #update content of page
            $filename = [System.IO.Path]::GetFileName($oldPath)
            $newContent = $vstsWikiTemplatesPathSyntax + $filename + "`n:::"
            $content = Get-Content $oldPath -Raw
            $footerContent = getFooterContent $content

            $newContent = $newContent + $footerContent
            Set-Content -Path $oldPath -Value $newContent
        }
    }
}

function addEmptyCategoryPageContent() {
    # add immediate children to category content (if category is empty)
    ForEach($name in $emptyCategoryFiles) {
        $path = $allPagesPathMap[$name]

        $childred = FetchChildrenForCategory $name
        If($name.StartsWith($mediaWikiCategoryPrefix)) {
            $displayName = $name.Remove(0, $mediaWikiCategoryPrefix.Length)
        } Else {
            $displayName = $name
        }
        $prependContent = ''#'List of pages under ' + $displayName + "`n"

        ForEach($child in $childred) {
                
            $fileName =  $child.title

            $pagePath = $allPagesPathMap[$fileName]
            if($pagePath) {
                $wikiPath = $pagePath.subString($localMachinePath.Length,$pagePath.Length - $localMachinePath.Length - 3)
                If($fileName.StartsWith($mediaWikiCategoryPrefix)) {
                    $fileName = $fileName.Remove(0, $mediaWikiCategoryPrefix.Length)
                }
                $text = '- [' + $fileName + '](' + $wikiPath + ')'
                $prependContent = $prependContent + $text + "`n"
            }
        }
        If($prependContent -ne '') {
            $content = Get-Content $path -Raw
        
            $prependContent = 'List of pages under ' + $displayName + ':' + "`n"+ $prependContent + "`n `n" 
            $content = $prependContent + $content
            Set-Content -Path $path -Value $content
        }
    }
}

function getAllImages() {
    $mediaWikiAllImagesArray = get-childitem $mediaWikiImageBackupPath -rec | where {!$_.PSIsContainer} | select-object FullName 

    New-Item -ItemType Directory -Force -Path $attachmentFolderPath

    ForEach($image in $mediaWikiAllImagesArray) {

        $imagePath = $image.FullName

        copy-item -path $imagePath -destination $attachmentFolderPath

    }
}

function removeRootCategoryPage() {
    If($allPagesPathMap.ContainsKey($rootCategory)) {
        $filePath = $allPagesPathMap[$rootCategory]
        Remove-Item $filePath
    }
}

function migrateToVSTSWiki() {
    Write-Host '---Fetching existing VSTS Wiki---'
    initializeGit # does NOT create wiki for now

    Write-Host '---Getting All Images---'
    getAllImages 
    Write-Host '---Creating PageHierarchy---' -ForegroundColor Cyan
    createPageHierarchy 
    
    Write-Host '---Getting content---' -ForegroundColor Cyan
    getContent
    #after this we shouldnt expect any hierarchy changes
    Write-Host '---Hierarchy freezed---' -ForegroundColor Cyan

    ForEach($pageName in $allPagesPathMap.Keys) {
        Write-Host 'Migrating page : '$pageName ' path is '$allPagesPathMap[$pageName] -ForegroundColor Cyan
        $path = $allPagesPathMap[$pageName]
        if(-not $donePaths.ContainsKey($path)) {
            if($path) {
            migratePage -path $path -pageName $pageName
            $donePaths.Add($path, $true)        
            }
        }
    }

    ForEach($pageName in $allTemplatesPathMap.Keys) {
        Write-Host 'Migrating template : '$pageName ' path is '$allTemplatesPathMap[$pageName] -ForegroundColor Cyan
        $path = $allTemplatesPathMap[$pageName]
        if(-not $donePaths.ContainsKey($path)) {
            if($path) {
            migrateTemplate -path $path -pageName $pageName
            $donePaths.Add($path, $true)
            }
        }
    }

    # add details of child pages to empty category pages - do not touch content pages
    addEmptyCategoryPageContent
    #Pages that are moved as templates
    CopyPagesToTemplatesFolder
    removeRootCategoryPage

    $finalizingScriptPath = $PSScriptRoot + '\.\finalize.ps1'
    if(Test-Path $finalizingScriptPath)
    {     
        & $finalizingScriptPath -allPagesPathMap $allPagesPathMap -allTemplatesPathMap $allTemplatesPathMap -mediaWikiCoreUrl $mediaWikiCoreUrl -localMachinePath $localMachinePath -renamedItems $renamedItems
    
    }

    Write-Host '---Pushing to  VSTS Wiki---'
    pushVSTSWiki
}

migrateToVSTSWiki