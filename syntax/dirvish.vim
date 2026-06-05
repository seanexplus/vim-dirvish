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
for p in argv()
  execute 'syntax match DirvishArg ,' .. escape(fnamemodify(p, ':p'), '[,* .. ^$~\') .. '$, contains=DirvishPathHead'
endfor

b:current_syntax = 'dirvish'
