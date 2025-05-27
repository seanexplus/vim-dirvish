vim9script
import autoload 'dirvish.vim' # as AutoDirvish
try
	call dirvish#Open()
catch /E121/
	echom "Error!"
endtry
if exists("b:did_ftplugin")
  finish
endif
b:did_ftplugin = 1

var nowait = (v:version > 703 ? '<nowait>' : '')
var sep = exists('+shellslash') && !&shellslash ? '\' : '/'

if !hasmapto('<Plug>(dirvish_quit)', 'n')
  execute 'nmap ' .. nowait .. '<buffer> q <Plug>(dirvish_quit)'
  execute 'nmap ' .. nowait .. '<buffer> gq <Plug>(dirvish_quit)'
endif
if !hasmapto('<Plug>(dirvish_arg)', 'n')
  execute 'nmap ' .. nowait .. '<buffer> x <Plug>(dirvish_arg)'
  execute 'xmap ' .. nowait .. '<buffer> x <Plug>(dirvish_arg)'
endif
if !hasmapto('<Plug>(dirvish_K)', 'n')
  execute 'nmap ' .. nowait .. '<buffer> K <Plug>(dirvish_K)'
  execute 'xmap ' .. nowait .. '<buffer> K <Plug>(dirvish_K)'
endif

var command_prefix = ':<C-U>'
var call_prefix = ':<C-U>.'
var cmdsuf = ":echon ''<CR>"
if has('nvim') || has('patch-8.2.1978')
  command_prefix = '<cmd>'
  call_prefix = '<cmd>'
  cmdsuf = ''
endif

execute 'nnoremap ' .. nowait .. '<buffer> ~    ' .. command_prefix .. 'Dirvish ~/<CR>' .. cmdsuf
execute 'nnoremap ' .. nowait .. '<buffer> i    ' .. call_prefix .. 'call dirvish#Open("edit", 0)<CR>' .. cmdsuf
execute 'nnoremap ' .. nowait .. '<buffer> <CR> ' .. call_prefix .. 'call dirvish#Open("edit", 0)<CR>' .. cmdsuf
execute 'nnoremap ' .. nowait .. '<buffer> a    ' .. call_prefix .. 'call dirvish#Open("vsplit", 1)<CR>' .. cmdsuf
execute 'nnoremap ' .. nowait .. '<buffer> o    ' .. call_prefix .. 'call dirvish#Open("split", 1)<CR>' .. cmdsuf
execute 'nnoremap ' .. nowait .. '<buffer> p    ' .. call_prefix .. 'call dirvish#Open("p", 1)<CR>' .. cmdsuf
execute 'nnoremap ' .. nowait .. '<buffer> <2-LeftMouse> ' .. call_prefix .. 'call Dirvish.Open("edit", 0)<CR>' .. cmdsuf
execute 'nnoremap ' .. nowait .. '<buffer><silent> dax  :<C-U>arglocal<Bar>silent! argdelete *<Bar>echo "arglist: cleared"<Bar>Dirvish<CR>'
execute 'nnoremap ' .. nowait .. '<buffer><silent> <C-n> <C-\><C-n>j:call feedkeys("p")<CR>'
execute 'nnoremap ' .. nowait .. '<buffer><silent> <C-p> <C-\><C-n>k:call feedkeys("p")<CR>'

if !has('nvim') && !has('patch-8.2.1978')
  call_prefix = ':'
endif
execute 'xnoremap ' .. nowait .. '<buffer> I    ' .. call_prefix .. 'call AutoDirvish.Open(<line1>, <line2>, "edit", 0)<CR>' .. cmdsuf
execute 'xnoremap ' .. nowait .. '<buffer> <CR> ' .. call_prefix .. 'call AutoDirvish.Open(<line1>, <line2>, "edit", 0)<CR>' .. cmdsuf
execute 'xnoremap ' .. nowait .. '<buffer> A    ' .. call_prefix .. 'call AutoDirvish.Open(<line1>, <line2>, "vsplit", 1)<CR>' .. cmdsuf
execute 'xnoremap ' .. nowait .. '<buffer> O    ' .. call_prefix .. 'call AutoDirvish.Open(<line1>, <line2>, "split", 1)<CR>' .. cmdsuf
execute 'xnoremap ' .. nowait .. '<buffer> P    ' .. call_prefix .. 'call AutoDirvish.Open(<line1>, <line2>, "p", 1)<CR>' .. cmdsuf

nnoremap <buffer><silent> R :<C-U><C-R>=v:count ? ': g:dirvish_mode=' .. v:count .. '<Bar>' : ''<CR>Dirvish<CR>
nnoremap <buffer><silent>   g?    :help dirvish-mappings<CR>

execute 'nnoremap <expr>' .. nowait .. '<buffer>  ..  ":<C-u>" .. (v:count ? "Shdo" .. (v:count?"!":"") .. " {}" : ("! " .. shellescape(empty(fnamemodify(getline(" .. "),": .. ")) ? " .. " : fnamemodify(getline(" .. "),": .. "), 1))) .. "<Home><C-Right>"'
execute 'xnoremap <expr>' .. nowait .. '<buffer>  ..  ":Shdo" .. (v:count?"!":" ") .. " {}<Left><Left><Left>"'
execute 'nnoremap <expr>' .. nowait .. '<buffer> cd ":<C-u>" .. (v:count ? "cd" : "lcd") .. " %<Bar>pwd<CR>"'

# Buffer-local / and ? mappings to skip the concealed path fragment.
if sep == '\'
  nnoremap <buffer> / /\ze[^\/]*[\/]\=$<Home>
  nnoremap <buffer> ? ?\ze[^\/]*[\/]\=$<Home>
else
  nnoremap <buffer> / /\ze[^/]*[/]\=$<Home>
  nnoremap <buffer> ? ?\ze[^/]*[/]\=$<Home>
endif

# Force autoload if `ft=dirvish`
if !exists('*Open')|try| dirvish#Open()|catch|endtry|endif
