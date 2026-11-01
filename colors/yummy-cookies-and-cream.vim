set background=dark
set termguicolors

hi clear

let g:colors_name = "yummy-cookies-and-cream"
let s:dark_gray   = "#222222"
let s:gray        = "#555555"
let s:cream       = "#fffdd0"
let s:raspberry   = "#d4688a"
let s:strawberry  = "#ff7f96"
let s:matcha      = "#a8c686"
let s:mint        = "#9fd8c4"
let s:mocha       = "#8e673e"
let s:chocolate   = "#c49a6c"
let s:cookie      = "#e6cea0"
let s:orange      = "#ffb877"
let s:butter      = "#f2d98d"

" Line Numbers
execute "hi CursorLineNr guifg=" . s:matcha . " guibg=" . s:dark_gray . " gui=bold"
execute "hi LineNrAbove  guifg=" . s:mint   . " guibg=" . s:dark_gray
execute "hi LineNrBelow  guifg=" . s:mint   . " guibg=" . s:dark_gray
set cursorline

" Cursor
execute "hi nCursor guifg= " . s:cream . " guibg=" . s:matcha
execute "hi iCursor guifg= " . s:cream . " guibg=" . s:cookie
execute "hi vCursor guifg= " . s:cream . " guibg=" . s:strawberry
set guicursor=n:block-nCursor,v:block-vCursor,c:block-nCursor,i:block-iCursor

" Normal text and background
execute "hi Normal      guifg=" . s:cream     . " guibg=" . s:dark_gray
execute "hi NormalNC    guifg=" . s:cream     . " guibg=" . s:dark_gray
execute "hi EndOfBuffer guifg=" . s:dark_gray . " guibg=" . s:dark_gray
execute "hi Visual      guifg=" . s:mocha     . " guibg=" . s:orange

" HTML headings and formatting
execute "hi htmlH1     guifg=" . s:cookie . " gui=underline guisp=" . s:chocolate
execute "hi htmlItalic guifg=" . s:cream  . " gui=italic"
execute "hi htmlBold   guifg=" . s:cream  . " gui=bold"

" Underlined text
execute "hi Underlined guifg=" . s:cookie . " guisp=" . s:chocolate . " gui=underline"

" Comments
execute "hi Comment guifg=" . s:cream . " gui=italic"

" Popup menu selection
hi PmenuSel cterm=underline,reverse gui=bold,reverse blend=0

" Directory names in Explore (Netrw)
execute "hi Directory guifg=" . s:cookie

" Common accent groups
execute "hi Identifier guifg=" . s:cookie
execute "hi Function   guifg=" . s:cookie
execute "hi Special    guifg=" . s:cookie

" Yummy
execute "hi YummyQuote             guifg=" . s:cookie     . " gui=italic"
execute "hi YummyName              guifg=" . s:butter     . " gui=bold"  
execute "hi YummyNameQuoted        guifg=" . s:mocha      . " gui=bold"  
execute "hi YummyChapter           guifg=" . s:chocolate  . " gui=bold"  
execute "hi YummyCharacterHeader   guifg=" . s:chocolate  . " gui=bold"  
execute "hi YummyCharacterAlias    guifg=" . s:cookie           
execute "hi YummyTabHeader         guifg=" . s:butter           
execute "hi YummyBlockquote        guifg=" . s:matcha     . " gui=italic"
execute "hi YummySongName          guifg=" . s:strawberry . " gui=bold"  
execute "hi YummySongArtist        guifg=" . s:strawberry 
execute "hi YummyTodo              guifg=" . s:raspberry
execute "hi YummyComment           guifg=" . s:matcha
execute "hi YummySeparator         guifg=" . s:chocolate  
execute "hi YummyPunctuation       guifg=" . s:mint  
execute "hi YummyPunctuationQuoted guifg=" . s:matcha  
