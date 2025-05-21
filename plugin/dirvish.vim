vim9script
if exists('g:loaded_dirvish') || &cp || v:version < 700 || &cpo =~# 'C'
  finish
endif
g:loaded_dirvish = 1

command! -bar -nargs=? -complete=dir Dirvish call dirvish#open(<q-args>)
command! -nargs=* -complete=file -range -bang Shdo call dirvish#shdo(<bang>0 ? argv() : getline(<line1>, <line2>), <q-args>)

def Isdir(dir: string): bool
  if &l:bufhidden =~# '\vunload|delete|wipe'
    return 0 # In a temporary special buffer (likely from a plugin).
  endif
  return !empty(dir) && (isdirectory(dir) ||
    \ (!empty($SYSTEMDRIVE) && isdirectory('/' .. tolower($SYSTEMDRIVE[0]) .. dir)))
enddef

augroup dirvish
  autocmd!
  # Remove netrw and NERDTree directory handlers.
  autocmd VimEnter * if exists('#FileExplorer') | execute 'au! FileExplorer *' | endif
  autocmd VimEnter * if exists('#NERDTreeHijackNetrw') | execute 'au! NERDTreeHijackNetrw *' | endif
  autocmd BufEnter * if !exists('b:dirvish') && Isdir(expand('%:p'))
    \ | Dirvish
    \ | elseif exists('b:dirvish') && &buflisted && bufnr('$') > 1 | setlocal nobuflisted | endif
  autocmd FileType dirvish if exists('#fugitive') | call FugitiveDetect(@%) | endif
  autocmd ShellCmdPost * if exists('b:dirvish') | Dirvish | endif
augroup END

nnoremap <silent> <Plug>(dirvish_up) :<C-U>exe 'Dirvish' fnameescape(fnamemodify(@%, ':p'.(@%[-1:]=~'[\\/]'?':h':'').repeat(':h',v:count1)))<CR>
nnoremap <silent> <Plug>(dirvish_split_up) :<C-U>split<bar>exe 'Dirvish' fnameescape(fnamemodify(@%, ':p'.(@%[-1:]=~'[\\/]'?':h':'').repeat(':h',v:count1)))<CR>
nnoremap <silent> <Plug>(dirvish_vsplit_up) :<C-U>vsplit<bar>exe 'Dirvish' fnameescape(fnamemodify(@%, ':p'.(@%[-1:]=~'[\\/]'?':h':'').repeat(':h',v:count1)))<CR>

highlight default link DirvishSuffix   SpecialKey
highlight default link DirvishPathTail Directory
highlight default link DirvishArg      Todo

if mapcheck('-', 'n') ==# '' && !hasmapto('<Plug>(dirvish_up)', 'n')
  nmap - <Plug>(dirvish_up)
endif
