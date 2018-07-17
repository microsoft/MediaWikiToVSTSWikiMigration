function New-CHashtable 
{ 
New-Object Collections.Hashtable ([StringComparer]::CurrentCulture) 
} 

#local
$orphanedPagesFolder = 'Orphaned pages'##vaaror- relook - why not Orphaned-pages
$separator = "\"
$mediaWikiRootCategory = "Hierarchy-Top"
$mediaWikiTemplatePrefix = "Template:"
$mediaWikiCategoryPrefix = "Category:"
$vstsWikiTemplatesDiskPath = ".templates\"
$vstsWikiTemplatesPathSyntax = "::: template /.templates/"
$mediaWikiPageNameKeyword = "PAGENAME"

$renamedPageRegEx = '\s*#REDIRECT\s*\[\[(.*)\]\]'

$mediaWikiGetAllCatgoriesPartialUrl = 'list=allcategories&action=query&aclimit=500&'
$mediaWikiAllCategoriesContinuationToken = 'accontinue'
$mediaWikiAllCategoriesContinuationTokenValue = ''

$rootCategory = "Category:Hierarchy Top"


$mediaWikiPageContentPartialUrl = 'action=query&prop=revisions&rvprop=content&titles='

$mediaWikiGetAllPagesPartialUrl = 'action=query&list=allpages&aplimit=500&'
$mediaWikiAllPagesContinuationToken = 'apcontinue'

$attachmentFolderName = '.attachments'