vim9script
var srcdir = expand('<sfile>:h:h:p')
var sep = exists('+shellslash') && !&shellslash ? '\' : '/'
var noswapfile = (2 == exists(':noswapfile')) ? 'noswapfile' : ''
var noau       = 'silent noautocmd keepjumps'
var cb_map = {}   # callback map
var rel = get(g:, 'dirvish_relative_paths', 0)
# Debug:
#     echo '' > dirvish.log ; tail -F dirvish.log
#     nvim +"let g:dirvish_dbg=1" -- b1 b2
#     :bnext
#     -
if get(g:, 'dirvish_dbg')
  def Log(msg: string, ...args: list<any>): void
    writefile([msg], expand('~/dirvish.log'), 'as')
  enddef
else
  def Log(msg: string, ...args: list<any>): void
  enddef
endif

def Msg_error(msg: string ): void
  redraw | echohl ErrorMsg | echomsg 'dirvish:' msg | echohl None
enddef

def Eq(dir1: string, dir2: string): bool
  return fnamemodify(dir1, ':p') ==# fnamemodify(dir2, ':p')
enddef

# Gets full path, or relative if g:dirvish_relative_paths=1.
def F(f: string): string
  var tf = fnamemodify(f, rel ? ':p:.' : ':p')
  # Special case: ":p:." yields empty for CWD.
  return !empty(tf) ? tf : fnamemodify(tf, ':p')
enddef

def Suf(): bool
  var m = get(g:, 'dirvish_mode', 1)
  return type(m) == type(0) && m <= 1 ? 1 : 0
enddef

# Normalizes slashe
# - Replace "\" with "/", for safe use of fnameescape(), isdirectory(). Vim bug #541.
# - Collapse slashes (except UNC-style \\foo\bar).
# - Always end dir with "/".
# - Special case: empty string (CWD) => "./".
def Sl(f: string): string
  var tf = has('win32') ? tr(f, '\', '/') : f
  # Collapse slashes (except UNC-style \\foo\bar).
  tf = tf[0] .. substitute(tf[1 :], '/\+', '/', 'g')
  # End with separator.
  return empty(tf) ? './' : (tf[-1 :] !=# '/' && isdirectory(tf) ? tf .. '/' : tf)
enddef

# Workaround for platform quirks, and shows an error if dir is invalid.
def Fix_dir(dir: string, silent: bool): string
  var tdir = Sl(dir)
  if !isdirectory(tdir)
    # Fallback for cygwin/MSYS paths lacking a drive letter.
    tdir = empty($SYSTEMDRIVE) ? tdir : '/' .. tolower($SYSTEMDRIVE[0]) .. (tdir)
    if !isdirectory(tdir)
      if !silent
        Msg_error("invalid directory: '" .. dir .. "'")
      endif
      return ''
    endif
  endif
  return tdir
enddef

def Parent_dir(f: string): string
  var f_noslash = substitute(f, escape(sep == '\' ? '[/\]' : '/', '\') .. '\+$', '', 'g')
  return Fix_dir(fnamemodify(f_noslash, ':h'), 0)
enddef

if v:version > 704 || v:version == 704 && has('patch279')
def Globlist(dir_esc: string, pat: string): list<string>
  return globpath(dir_esc, pat, !Suf(), 1)
enddef
else # Older versions cannot handle filenames containing newlines.
def Globlist(dir_esc: string, pat: string): list<string>
  return split(globpath(dir_esc, pat, !Suf()), "\n")
enddef
endif

def List_dir(dir: string): any
  rel = get(g:, 'dirvish_relative_paths', 0)
  # Escape for globpath().
  var dir_esc = escape(substitute(dir, '\[', '[[]', 'g'), ',;*?{}^$\')
  var paths = Globlist(dir_esc, '*')
  # Append dot-prefixed files. globpath() cannot do both in 1 pass.
  paths = paths + Globlist(dir_esc, '.[^.]*')

  if rel && !Eq(dir, Parent_dir(Sl(getcwd())))  # Avoid blank CWD.
    return map(paths, "fnamemodify(v:val, ':p:.')")
  else
    return map(paths, "fnamemodify(v:val, ':p')")
  endif
enddef

def Info(paths: list<string>, dirsize: number): void
  for f in paths
    # Slash decides how getftype() classifies directory symlinks. #138
    var noslash = substitute(f, escape(sep,'\').'$', '', 'g')
    var fname = len(paths) < 2 ? '' : printf('%12.12s ',fnamemodify(substitute(f,'[\\/]\+$','',''),':t'))
    var size = (-1 != getfsize(f) && dirsize ? matchstr(system('du -hs '.shellescape(f)),'\S\+') : printf('%.2f',getfsize(f)/1000.0).'K')
    echo (-1 == getfsize(f) ? '?' : (fname .. (getftype(noslash)[0]) .. ' ' .. getfperm(f)
          \ .. ' ' .. strftime('%Y-%m-%d.%H:%M:%S',getftime(f)) .. ' ' .. size) .. ('link'!=#getftype(noslash)?'':' -> ' .. fnamemodify(resolve(f),':~:.')))
  endfor
enddef

def Set_args(args: list<string>): void
  if exists('*arglistid') && arglistid() == 0
    arglocal
  endif
  var normalized_argv = map(argv(), 'fnamemodify(v:val, ":p")')
  for f in args
    var i = index(normalized_argv, f)
    if -1 == i
      execute '$argadd '.. fnameescape(fnamemodify(f, ':p'))
    elseif 1 == len(args)
      execute (i+1) .. 'argdelete'
      syntax clear DirvishArg
    endif
  endfor
  echo 'arglist: ' .. argc() .. ' files'

  # Define (again) DirvishArg syntax group.
  execute 'source '.. fnameescape(srcdir.'/syntax/dirvish.vim')
enddef

export def Shdo(paths: list<string>, cmd: string): void
  # Remove empty/duplicate lines.
  var lines = uniq(sort(filter(copy(paths), '-1!=match(v:val,"\\S")')))
  var head = fnamemodify(get(lines, 0, '')[:-2], ':h')
  var jagged = 0 != len(filter(copy(lines), 'head != fnamemodify(v:val[:-2], ":h")'))
  if empty(lines) | Msg_error('Shdo: no files') | return | endif

  var dirvish_bufnr = bufnr('%')
  var cmd = cmd =~# '\V{}' ? cmd : (empty(cmd)?'{}':(cmd.' {}')) # DWIM
  # Paths from argv() or non-dirvish buffers may be jagged; assume CWD then.
  var dir = jagged ? getcwd() : head
  var tmpfile = tempname().(&sh=~?'cmd.exe'?'.bat':(&sh=~'\(powershell\|pwsh\)'?'.ps1':'.sh'))

  for i in range(0, len(lines)-1)
    var f = substitute(lines[i], escape(sep,'\').'$', '', 'g') "trim slash
    if !filereadable(f) && !isdirectory(f)
      var lines[i] = '#invalid path: ' .. shellescape(f)
      continue
    endif
    var f = !jagged && 2==exists(':lcd') ? fnamemodify(f, ':t') : lines[i]
    var lines[i] = substitute(cmd, '\V{}', escape(shellescape(f),'&\'), 'g')
  endfor
  execute 'silent split' tmpfile '|' (2==exists(':lcd')?('lcd ' .. dir):'')
  setlocal bufhidden=wipe
  silent keepmarks keepjumps setline(1, lines)
  silent write
  if executable('chmod')
    system('chmod u+x ' .. tmpfile)
    silent edit
  endif

  augroup dirvish_shcmd
    autocmd! * <buffer>
    # Refresh Dirvish after executing a shell command.
    exe 'autocmd ShellCmdPost <buffer> nested if !v:shell_error && bufexists(' .. dirvish_bufnr .. ')'
      .. '|setlocal bufhidden=hide|buffer ' .. dirvish_bufnr .. '|silent! Dirvish'
      .. '|buffer ' .. bufnr('%') .. '|setlocal bufhidden=wipe|endif'
  augroup END

  nnoremap <buffer><silent> Z! :silent write<Bar>exe '!' .. (has('win32') ? fnameescape(escape(expand('%:p:gs?\\?/?'), '&\')):join(map(split(&shell), 'shellescape(v:val)')) .. ' %')<Bar>if !v:shell_error<Bar>close<Bar>endif<CR>
enddef

# Returns true if the buffer was modified by the user.
def Buf_modified(): bool
  return b:changedtick > get(b:dirvish, '_c', b:changedtick)
enddef

def Buf_init(): void
  augroup dirvish_buflocal
    autocmd! * <buffer>
    autocmd BufEnter,WinEnter <buffer> call On_bufenter()
    if exists('##TextChanged')
      autocmd TextChanged,TextChangedI <buffer> if Buf_modified()
            \ && has('conceal') | execute 'setlocal conceallevel=0' | endif
    endif

    # BufUnload is fired for :bwipeout/:bdelete/:bunload, _even_ if
    # 'nobuflisted'. BufDelete is _not_ fired if 'nobuflisted'.
    # NOTE: For 'nohidden' we cannot reliably handle :bdelete like this.
    if &hidden
      autocmd BufUnload <buffer> call on_bufunload()
    endif
  augroup END

  setlocal buftype=nofile noswapfile
enddef

def On_bufenter(): void
  if bufname('%') is ''  # Something is very wrong. #136
    return
  elseif !exists('b:dirvish') || (empty(getline(1)) && 1 == line('$'))
    Dirvish
  elseif 3 != &l:conceallevel && !Buf_modified()
    Win_init()
  else
    # Ensure w:dirvish for window splits, `:b <nr>`, etc.
    w:dirvish = extend(get(w:, 'dirvish', {}), b:dirvish, 'keep')
  endif
enddef

def Save_state(d: dict<any>): void
  # Remember previous ('original') buffer.
  var p = Buf_valid(bufnr('%')) || !exists('w:dirvish') ? 0 + bufnr('%') : w:dirvish.prevbuf
  if !Buf_valid(p)
    # If reached via :edit/:buffer/etc. we cannot get the (former) altbuf.
    p = exists('b:dirvish') && Buf_valid(b:dirvish.prevbuf) ? b:dirvish.prevbuf : bufnr('#')
  endif

  # Remember alternate buffer.
  var a = (p != bufnr('#') && Buf_valid(bufnr('#'))) || !exists('w:dirvish') ? 0 + bufnr('#') : w:dirvish.altbuf
  if !Buf_valid(a) || a == p
    a = exists('b:dirvish') && Buf_valid(b:dirvish.altbuf) ? b:dirvish.altbuf : -1
  endif

  # Save window-local settings.
  d.altbuf = a
  d.prevbuf = p
  w:dirvish = extend(get(w:, 'dirvish', {}), d, 'force')
  [w:dirvish._w_wrap, w:dirvish._w_cul] = [&l:wrap, &l:cul]
  if has('conceal') && !exists('b:dirvish')
    [w:dirvish._w_cocu, w:dirvish._w_cole] = [&l:concealcursor, &l:conceallevel]
  endif

  Log(printf('save_state: bufnr=%d altbuf=%d prevbuf=%d', bufnr(''), d.altbuf, d.prevbuf))
enddef

def Win_init(): void
  w:dirvish = extend(get(w:, 'dirvish', {}), b:dirvish, 'keep')
  setlocal nowrap cursorline

  if has('conceal')
    setlocal concealcursor=nvc conceallevel=2
  endif
enddef

def On_bufunload(): void
  Restore_winlocal_settings()
enddef

def Buf_close(): void
  var d = get(w:, 'dirvish', {})
  if empty(d)
    return
  endif

  var [altbuf, prevbuf] = [get(d, 'altbuf', 0), get(d, 'prevbuf', 0)]
  Log(printf('buf_close: bufnr=%d altbuf=%d prevbuf=%d', bufnr(''), altbuf, prevbuf))
  var found_alt = try_visit(altbuf, 0)
  if !try_visit(prevbuf, 0) && !found_alt
      \ && (1 == bufnr('%') || (prevbuf != bufnr('%') && altbuf != bufnr('%')))
    bdelete
  endif
enddef

def Restore_winlocal_settings(): void
  if !exists('w:dirvish') # can happen during VimLeave, etc.
    return
  endif
  if has('conceal') && has_key(w:dirvish, '_w_cocu')
    var [&l:cocu, &l:cole] = [w:dirvish._w_cocu, w:dirvish._w_cole]
  endif
enddef

def Open_selected(splitcmd: string, bg: number, line1: number, line2: number): void
  var curbuf = bufnr('%')
  var [curtab, curwin, wincount] = [tabpagenr(), winnr(), winnr('$')]
  var p = (splitcmd ==# 'p')  # Preview-mode

  var paths = getline(line1, line2)
  for path in paths
    var isdir = path[-1 :] == sep
    if !isdirectory(path) && !filereadable(path)
      Msg_error(printf('invalid (access denied?): %s', path))
      continue
    endif
    # Open files (not dirs) using relative paths.
    var shortname = fnamemodify(path, isdir ? ':p:~' : ':~:.')

    if p  # Go to previous window.
      execute (winnr('$') > 1 ? 'wincmd p|if winnr()==' .. winnr() .. '|wincmd w|endif' : 'vsplit')
    endif

    if isdir
      execute (p || splitcmd ==# 'edit' ? '' : splitcmd .. '|') 'Dirvish' fnameescape(shortname)
    else
      execute (p ? 'edit' : splitcmd) fnameescape(shortname)
    endif

    # Return to previous window after _each_ split, else we get lost.
    if bg && (p || (splitcmd =~# 'sp' && winnr('$') > wincount))
      wincmd p
    endif
  endfor

  if bg # return to dirvish buffer
    if splitcmd ==# 'tabedit'
      execute 'tabnext' curtab '|' curwin .. 'wincmd w'
    elseif splitcmd ==# 'edit'
      execute 'silent keepalt keepjumps buffer' curbuf
    endif
  elseif !exists('b:dirvish') && exists('w:dirvish')
    Set_altbuf(w:dirvish.prevbuf)
  endif
enddef

def Set_altbuf(bnr: number): void
  if !Buf_valid(bnr) | return | endif

  if has('patch-7.4.605') | @# = bnr | return | endif

  var curbuf = bufnr('%')
  if Try_visit(bnr, 1)
    var tnoau = bufloaded(curbuf) ? 'noau' : ''
    # Return to the current buffer.
    execute 'silent keepjumps' tnoau noswapfile 'buffer' curbuf
  endif
enddef

def Try_visit(bnr: any, fnoau: number): number
  if Buf_valid(bnr)
    # If _previous_ buffer is _not_ loaded (because of 'nohidden'), we must
    # allow autocmds (else no syntax highlighting; #13).
    var tnoau = fnoau && bufloaded(bnr) ? 'noau' : ''
    execute 'silent keepjumps' tnoau noswapfile 'buffer' bnr
    return 1
  endif
  return 0
enddef

if exists('*win_execute')
  # Performs `cmd` in all windows showing `bnr`.
  def Bufwin_do(cmd: string, bnr: number): void
    map(filter(getwininfo(), (k, v) => bnr ==# v.bufnr), (k, v) => win_execute(v.winid, noau .. ' ' .. cmd))
  enddef
else
  def Tab_win_do(tnr: number, cmd: string, bnr: any): void
    execute noau 'tabnext' tnr
    for wnr in range(1, tabpagewinnr(tnr, '$'))
      if bnr ==# winbufnr(wnr)
        execute noau wnr .. 'wincmd w'
        execute cmd
      endif
    enddefor
  enddef

  def Bufwin_do(cmd: string, bnr: number): void
    var [curtab, curwin, curwinalt, curheight, curwidth, squashcmds] = [tabpagenr(), winnr(), winnr('#'), winheight(0), winwidth(0), filter(split(winrestcmd(), '|'), 'v:val =~# " 0$"')]
    for tnr in range(1, tabpagenr('$'))
      var [origwin, origwinalt] = [tabpagewinnr(tnr), tabpagewinnr(tnr, '#')]
      for bnr in tabpagebuflist(tnr)
        if bnr == bnr
          Tab_win_do(tnr, cmd, bnr)
          execute noau origwinalt .. 'wincmd w|' noau origwin.'wincmd w'
          break
        endif
      endfor
    endfor
    execute noau 'tabnext ' .. curtab
    execute noau curwinalt .. 'wincmd w|' noau curwin .. 'wincmd w'
    if (&winminheight == 0 && curheight != winheight(0)) || (&winminwidth == 0 && curwidth != winwidth(0))
      for squashcmd in squashcmds
        if squashcmd =~# '^\Cvert ' && winwidth(matchstr('\d\+', squashcmd)) != 0
          \ || squashcmd =~# '^\d' && winheight(matchstr('\d\+', squashcmd)) != 0
          execute noau squashcmd
        endif
      endfor
    endif
  enddef
endif

def Buf_render(dir: string, lastpath: string): void
  var bnr = bufnr('%')
  var isnew = empty(getline(1))

  if !isdirectory(dir)
    echoerr 'dirvish: not a directory:' dir
    return
  endif

  if !isnew
    Bufwin_do('let w:dirvish["_view"] = winsaveview()', bnr)
  endif

  if v:version > 704 || v:version == 704 && has("patch73")
    setlocal undolevels=-1
  endif
  silent keepmarks keepjumps :%delete _
  silent keepmarks keepjumps setline(1, List_dir(dir))
  if type("") == type(get(g:, 'dirvish_mode'))  # Apply user's filter.
    execute get(g:, 'dirvish_mode')
  endif
  if v:version > 704 || v:version == 704 && has("patch73")
    setlocal undolevels<
  endif

  if !isnew
    Bufwin_do('call winrestview(w:dirvish["_view"])', bnr)
  endif

  if !empty(lastpath)
    var pat = tr(F(lastpath), '/', sep)  # platform slashes
    search('\V\^' .. escape(pat, '\') .. '\$', 'cw')
  endif
  # Place cursor on the tail (last path segment).
  search('\' .. sep .. '\zs[^\' .. sep .. ']\+\' .. sep .. '\?$', 'c', line('.'))

  # TRICK: From :help getfperm(): "If the directory cannot be read, empty string is returned."
  # This misses the "--x" case (no "r" access), but it's the best we have.
  if empty(getline(1)) && '' ==# getfperm(dir .. '/.')
    Msg_error(printf('cannot list directory (permission %s): %s', getfperm(dir), dir))
  endif
enddef

def Apply_icons(): void
  if 0 == len(cb_map)
    return
  endif
  var prop_type = ''
  var feat = has('nvim-0.8') ? 'extmark' : ((v:version >= 901 && has('textprop')) ? 'textprop' : 'conceal')
  if feat ==# 'extmark'
    # if !exists('ns_id')
    #   var ns_id = nvim_create_namespace('dirvish.icons')
    # endif
  elseif feat ==# 'textprop'
    if !exists('prop_type')
      prop_type = 'dirvish.icons'
      prop_type_add(prop_type, {})
    endif
  else
    highlight clear Conceal
  endif

  var i = 0
  for f in getline(1, '$')
    i += 1
    var icon = ''
    for id in sort(keys(cb_map))
      icon = cb_map[id](f)
      if -1 != match(icon, '\S')
        break
      endif
    endfor
    if icon != ''
      if feat ==# 'extmark'
        # nvim_buf_set_extmark(0, ns_id, i-1, 0, {virt_text: [[icon, 'DirvishColumnHead']], virt_text_po 'inline'})
      elseif feat ==# 'textprop'
        prop_add(i, 1, {type: prop_type, text: icon})
      else
        var isdir = (f[-1 :] == sep)
        var tf = substitute(F(f), escape(sep, '\') .. '$', '', 'g')  # Full path, trim slash.
        var tail_esc = escape(fnamemodify(tf, ':t') .. (isdir ? (sep) : ''), '[,*.^$~\')
        execute 'syntax match DirvishColumnHead =\%' .. i .. 'l^.\{-}\ze' .. tail_esc .. '$= conceal cchar=' .. icon
      endif
    endif
  endfor
enddef

var recursive = ''
def Open_dir(d: dict<any>, reload: bool): void
  if recursive ==# d._dir
    return
  endif
  recursive = d._dir
  Log(printf('open_dir ENTER: %d %s', bufnr('%'), d._dir))
  # var d = d
  var dirname_without_sep = substitute(d._dir, '[\\/]\+$', '', 'g')

  # Vim tends to 'simplify' buffer names. Examples (gvim 7.4.618):
  #     ~\foo\, ~\foo, foo\, foo
  # Try to find an existing buffer before creating a new one.
  var bnr = -1
  for pat in ['', ':~:.', ':~']
    var dir = fnamemodify(d._dir, pat)
    if dir == '' | continue | endif
    bnr = bufnr('^' .. dir .. '$')
    if -1 != bnr
      break
    endif
  endfor

  # Note: :noautocmd not used here, to allow BufEnter/BufNew. 61282f2453af
  # Thus recursive guards against recursion (for performance).
  if -1 == bnr
    execute 'silent' noswapfile 'keepalt edit' fnameescape(d._dir)
  else
    execute 'silent' noswapfile 'buffer' bnr
  endif

  # Force a normalized directory path.
  # - Starts with "~/" or "/", ie absolute (important for ":h").
  # - Ends with "/".
  # - Avoids ".././..", ".", "./", etc. (breaks %:p, not updated on :cd).
  # - Avoids [Scratch] in some cases (":e ~/" on Windows).
  if bufname('%')[-1 :] != '/' ||  bufname('%')[0 : 1] !=# d._dir[0 : 1]
    execute 'silent' noswapfile 'file' fnameescape(d._dir)
  endif

  if !isdirectory(bufname('%'))  # sanity check
    throw 'invalid directory: ' .. bufname('%')
  endif

  if &buflisted && bufnr('$') > 1
    setlocal nobuflisted
  endif

  Set_altbuf(d.prevbuf) #in case of :bd, :read#, etc.

  b:dirvish = exists('b:dirvish') ? extend(b:dirvish, d, 'force') : d

  Buf_init()
  Win_init()
  if reload || Should_reload()
    Buf_render(b:dirvish._dir, get(b:dirvish, 'lastpath', ''))
    # Set up Dirvish before any other `FileType dirvish` handler.
    execute 'source ' .. fnameescape(srcdir .. '/ftplugin/dirvish.vim')
    var curwin = winnr()
    setlocal filetype=dirvish
    if curwin != winnr() | throw 'FileType autocmd changed the window' | endif
    b:dirvish._c = b:changedtick
    Apply_icons()
  endif
  recursive = ''
  Log(printf('open_dir EXIT : %d %s', bufnr('%'), d._dir))
enddef

def Should_reload(): bool
  return !Buf_modified() || (empty(getline(1)) && 1 == line('$'))
enddef

def Buf_valid(bnr: any): bool
  return bufexists(bnr) && (empty(bufname(bnr)) || !isdirectory(Sl(bufname(bnr))))
enddef

export def Testfunc(msg: string): void
	echom msg
enddef

export def Open(...args: list<any>): void
  if len(args) == 0 | return | endif
  if &autochdir
    Msg_error("'autochdir' is not supported")
    return
  endif
  if (&bufhidden =~# '\vunload|delete|wipe' || (!&autowriteall && !&hidden && &modified))
      \ && (!exists("*win_findbuf") || len(win_findbuf(winbufnr(0))) == 1)
    Msg_error(&modified ? 'E37: No write since last change' : 'E37: Buffer would be deleted: ' .. bufnr('%'))
    return
  endif
  if len(args) > 1
    # Detect whether a <Cmd> mapping or the legacy fallback is being used
    var visual_lines = mode(0) == 'n' ? [line("."), line(".")] : [line('v'), line('.')]
    Open_selected(args[0], args[1], min(visual_lines), max(visual_lines))
    return
  endif

  var d = {}
  var is_uri    = -1 != match(args[0], '^\w\+:[\/][\/]')
  var from_path = Sl(fnamemodify(bufname('%'), ':p'))
  var to_path   = Sl(fnamemodify(!empty(args[0]) || empty(@%) ? args[0] : @%, ':p'))

  d._dir = Fix_dir(filereadable(to_path) ? fnamemodify(to_path, ':p:h') : to_path, is_uri)
  # Fallback to CWD for URIs. #127
  d._dir = empty(d._dir) && is_uri ? Fix_dir(getcwd(), is_uri) : d._dir
  if empty(d._dir)  # fix_dir() already showed error.
    return
  endif

  var reloading = exists('b:dirvish') && d._dir ==# b:dirvish._dir && recursive !=# d._dir

  if reloading
    d.lastpath = ''         # Do not place cursor when reloading.
  elseif !is_uri && Eq(d._dir, Parent_dir(from_path))
    d.lastpath = from_path  # Save lastpath when navigating _up_.
  endif

  Save_state(d)
  Open_dir(d, reloading)
enddef

export def Add_icon_fn(fn: any): void
  if !exists('v:t_func') || type(fn) != v:t_func | throw 'argument must be a Funcref' | endif
  var cb_map[string(fn)] = fn
  return string(fn)
enddef

export def Remove_icon_fn(fn_id: string): number
  if has_key(cb_map, fn_id)
    remove(cb_map, fn_id)
    return 1
  endif
  return 0
enddef

nnoremap <silent> <Plug>(dirvish_quit) :<C-U>call <ScriptCmd>Buf_close()<CR>
nnoremap <silent> <Plug>(dirvish_arg) :<C-U>call <ScriptCmd>Set_args([getline('.')])<CR>
xnoremap <silent> <Plug>(dirvish_arg) :<C-U>call <ScriptCmd>Set_args(getline("'<", "'>"))<CR>
nnoremap <silent> <Plug>(dirvish_K) :<C-U>call <ScriptCmd>Info([getline('.')],!!v:count)<CR>
xnoremap <silent> <Plug>(dirvish_K) :<C-U>call <ScriptCmd>Info(getline("'<", "'>"),!!v:count)<CR>
