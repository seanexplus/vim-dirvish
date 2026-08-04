vim9script
if 'dirvish' !=# get(b:, 'current_syntax', 'dirvish')
  finish
endif

var sep = has('win32') && stridx(fnamemodify('.', ':p'), '\') >= 0 ? '\\' : '/'
var escape = 'substitute(escape(v:val, ".$~"), "*", ".*", "g")'

# Define once (per buffer).
if !exists('b:current_syntax')
  execute 'syntax match DirvishPathHead =.*' .. sep .. '\ze[^' .. sep .. ']\+' .. sep .. '\?$= conceal'
  execute 'syntax match DirvishPathTail =[^' .. sep .. ']\+' .. sep .. '$='
  execute 'syntax match DirvishSuffix   =[^' .. sep .. ']*\%(' .. join(map(split(&suffixes, ','), escape), '\|')  ..  '\)$='
endif

# Define (again) ..  Other windows (different arglists) need the old definitions .. 
# Do these last, else they may be overridden (see :h syn-priority) .. 
var rel = exists('g:dirvish_relative_paths')
for p in argv()
  var f = rel ? fnamemodify(p, ':p:.') : fnamemodify(p, ':p')
  execute 'syntax match DirvishArg ,' .. escape(f, '[,* .. ^$~\') .. '$, contains=DirvishPathHead'
endfor

b:current_syntax = 'dirvish'
