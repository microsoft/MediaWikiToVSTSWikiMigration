This document contains the details of the content migrated from mediawiki based [VSOWiki](https://vsowiki.com/) to markdown based [VSTSWiki](https://mseng.visualstudio.com/VSOnline/VS.in%20Social%20Collab/_wiki/wikis/VSOnline.wiki). We migrated around 3500 pages from VSOWiki to VSTS Wiki.

This article details out:

1. Learnings from the migration
2. Manual fixes we had to do 
3. Not supported formats even after the migration
4. Automated fixes

# Learnings

Our [automation tool](https://github.com/vashitaArora/mediawikiToVstsWiki/blob/master/README.md) is built on [pandoc](pandoc.org).I have discussed our strategy and key decisions we made before the migration in this [PPT](https://github.com/vashitaArora/mediawikiToVstsWiki/blob/master/VSOWiki-VSTSWiki-FeatureComparefrGitHub.pptx) for broader reference. 




# Manual fixes
There are certain issues that were not automatically fixed during migration since either those were too taxing to automate or the impact of the issue was limited to only a handful of pages. The expectation is that users will fix those pages in VSTSWiki if they encounter an issue.

## Tables

-----------

**ISSUE:** If tables in mediawiki contain a pipe operator ```|``` within the content of a cell, then such tables may not appear fine since a pipe operator in markdown is considered as the beginning of a new cell. 

**MITIGATION**: Remove any unnecessary pipe operators in VSTSWiki for table to render well. In case the ```|``` is required in the table, then prefix it with a ```\ backslash``` which is the escape symbol for markdown.


--------------

**ISSUE:** If tables in mediawiki contain merged cells, then such tables may not appear fine in VSTS WIki since current markdown capability in VSTS does not support merged cells. 

**MITIGATION**: Consider simplifying the table to avoid merged cells or if the merged cells are required in the table then consider copying the table as HTML.  Use the **Paste as HTML** feature in VSTS Wiki to copy complex tables as HTML.

 
 
------

## Line breaks

**ISSUE:** [MediaWiki ignores single line breaks](https://www.mediawiki.org/wiki/Help:Formatting) while currently VSTS markdown does not therefore you may see unintended line breaks in VSTS Wiki. 

**MITIGATION:** Remove unintended line breaks in markdown 

## Indentation

**ISSUE:** MediaWiki uses `:` for indentation. Currently there are very few pages in mediawiki that use `:` for indentation therefore this is not supported during migration.

**MITIGATION:** Evaluate the need for indentation of content. Markdown in VSTS Wiki also supports HTML tags therefore you can use `&nbsp` for tabs or indentation. This is applicable for aligning images in VSTS Wiki as well.

## Title syntax containing ```=```
**ISSUE** Section headers containing `=` sign in the text such as '`Section name = foobar` may not appear in correct format since migration scripts assume `=` sign as the beginning of another section. Such a title would appear as follows in VSTS wiki `==Section name = foobar==`

**MITIGATION** Simply remove the `==` at the beginning and ending of the title.

# Not supported

The following syntax or user experiences will not be supported or migrated to VSTS Wiki. 

1. ```<script> </script>``` tags are not supported in VSTS markdown due to security reasons.
2. **Bold** content inside `code blocks` is not supported due to low usage.
3.  Image titles in mediawiki such as one shown below ..."Send a smile Feedback" appear as tool tips on images in markdown.
4. Redirect pages are not migrated since these add to unnecessary clutter in VSTSWiki. Instead we have a rich filter and search experience that will allow you to find the page of your choice easily.
5. Mediawiki supports section edits i.e. you can edit a section instead of the whole page. This capability is not supported in VSTS Wiki.
6. User pages in mediawiki will not be migrated to VSTS Wiki since mostly these pages are not containing useful information. There may be users who have some meaningful information on their user page. In such cases we expect users to migrate those pages manually.

# Automated fixes
In a nut shell, we automated the rest of the migration from mediawiki to VSTS wiki using http://pandoc.org/. 

## Content
All content in mediawiki format will be viewable in markdown format.

## Hierarchy
VSTS Wiki supports a very rich tree based hierarchical structure which mediawiki supports a graph based hierarchical structure that is constructed based on the category tree. The basic difference is that since mediawiki hierarchy is graph based you can have the same page be part of two different categories therefore it may appear under two different hierarchies in the tree. The migration tool translates and simplifies this hierarchy structure and transforms the graph based hierarchy into a tree based hierarchy. You may also find a node in tree called **Orphaned pages**. These are all the pages that are not linked to any hierarchy.



Credits: http://pandoc.org/