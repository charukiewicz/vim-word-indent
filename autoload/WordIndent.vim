  vim9script

  const default_pairs = {'(': ')', '[': ']', '{': '}', '''': '''', '"': '"'}

# find tab stop for a given line
# breaking words 
export def FindWordStops(str: string): list<number>
  var stops = []
  var was_blank = true
  const l = strlen(str)
  var pos = 0
  const pairs = get(b:, 'word_indent_pairs', default_pairs)
  while (pos < l)
    const c = str[pos]
    pos += 1
    var cclass = charclass(c)
    var pair = pairs->get(c, null)
    if  (was_blank || pair != null)
      if (cclass == 0) # blank
        continue
      endif

      was_blank = false
      stops->add(pos)
      if (pair == null || pos == l) 
        # normal meet a word or last character
      else # parenthesis, skip til matching
        var level = 1
        for pos2 in range(pos, l - 1)
          const cursor = str[pos2]
          if (cursor == c)
            level += 1
          elseif (cursor == pair)
            level -= 1
            if (level <= 0 || pair == c )
              #               ' or " no nesting
              # closed pair found skip to next character
              pos = pos2 + 1
              break
            endif
          endif
        endfor
      endif
    else
      if (cclass == 0) 
        was_blank = true
      endif
    endif
  endwhile

  return stops
enddef

def Line(lnum: string, offset: number): number
  if lnum == ''
    return offset
  endif
  return line(lnum) + offset
enddef

# Find words from given line (and recursively
# line above if a line is indented
# Ex
#
#   A1    A2    A3
#            B1    B2
#               C1    C2
#   *     *  *  *     *
#   Returns
#   A1 A2 B1 C1 C2
#     
export def FindTabStopsR(lnum: string, offset: number): list<number>
  var l: number = Line(lnum, offset)
  var stops = FindWordStops(getline(l))
  var left = stops->get(0, 1000)
  while (left > 1 && l > 0)
    l = l - 1
    const new_stops = FindWordStops(getline(l))
    const first_bad = new_stops->indexof((i, v) => v >= left)
    const lefts = new_stops->slice(0, first_bad)
    stops = lefts + stops
    left = stops->get(0, left)
  endwhile
  # remove 1
  const i1 = stops->index(1)
  if i1 > -1
    stops->remove(i1)
  endif
  return stops
enddef

export def SetWordStops(lnum: string, offset: number = 0): any
  const stops: list<number> = FindTabStopsR(lnum, offset)
  var diffs: list<number> = []
  var last = 1
  for stop in stops
    if stop != last 
      diffs->add(stop - last)
    endif
    last = stop
  endfor
  &vartabstop = diffs->join(',')
  &colorcolumn = stops->join(',')
  return stops
enddef

# 1,4,6,9 => xxxx..xxx
def StopsToZebra(stops: list<number>): list<number>
  var cols = []
  var start =  0
  for stop in stops
    if (start > 0)
      cols = cols + range(start, stop - 1)
      start = 0
    else
      start = stop
    endif
  endfor
  return cols
enddef

export def ColsToTabStops(cols: list<number>): list<number>
  var last = 1
  var stops = []
  for col in cols
    if col != last
      stops->add(col - last)
    endif
    last = col
    endfor
  return stops
enddef

export def TabStopsToCols(stops: list<number>): list<number>
  var cols = []
  var col = 1
  for stop in stops 
    col += stop
    cols->add(col)
  endfor
  return cols
enddef

# set colorculum
export def SetCcFromVsts()
  &colorcolumn = &varsofttabstop->StrToNrs()->TabStopsToCols()->join(',')
enddef

# varsofttabstop
export def SetVstsFromCc()
  &varsofttabstop = &colorcolumn->StrToNrs()->ColsToTabStops()->join(',')
enddef

def StrToNrs(str: string): list<number>
  return str->split(',')->map((key, val) => str2nr(val))
enddef


export def AddCc()
  var cols = &colorcolumn->StrToNrs()
  const col = getcurpos()[2]
  const i = cols->index(col)
  if i == -1
    cols->add(col)
  else
    cols->remove(i)
  endif
  SetCcs(cols)
enddef

export def SetCc()
  const col = getcurpos()[2]
  SetCcs([col])
enddef

def SetCcs(cols: list<number>)
  &colorcolumn = cols->copy()->sort('N')->join(',')
  if get(g:, 'word_indent_auto_vsts', 1) != 0
    &varsofttabstop = cols->ColsToTabStops()->join(',')
  endif
enddef


# get stops from &colorcolumn or &varsoftabs
export def GetStops(): list<number>
  const cols = &colorcolumn->StrToNrs()
  if len(cols) > 0
    return cols
  endif
  return &varsofttabstop->StrToNrs()->TabStopsToCols()
enddef

# use last stops unless
# the line is already matching a stop
export def Indent(): number
  # 0 indent if previous line empty
  if getline(v:lnum - 1) == ""
    return 0
  endif
  var stops = GetStops()
  if len(stops) == 0
    stops = FindTabStopsR('', v:lnum - 1)
  endif

  if len(stops) == 0
    stops = [1]
  endif

  const current_indent: number = indent(v:lnum) + 1
  const current_stop: number = stops->FindNextStops(current_indent)

  if current_stop == current_indent
    # at a stop, don't change it
    return current_stop - 1
  elseif current_stop > 0
    return current_stop - 1
  endif 
  return stops[-1] - 1
enddef

export def ToggleIndent()
  if &indentexpr == "indentexpr=WordIndent#Indent()"
    :set indentexpr=
  else
    :set indentexpr=WordIndent#Indent()
  endif
enddef


# Find first stops >= given position
export def FindNextStops(stops: list<number>, pos: number): number
  const i = stops->indexof('v:val >= ' .. pos)
  if i > -1
    return stops[i]
  endif
  return 0
enddef

export def FindPreviousStops(stops: list<number>, pos: number): number
  const i = stops->indexof('v:val >= ' .. pos)
  if i == -1
    return stops[-1]
  elseif i > 0
    return stops[i - 1 ]
  endif
  return 0
enddef

# set sw so that the next shift will align the first character to with the
# next/previous tab and execute the action
export def WithShift(dir: string, cmd: string)
  const stops = GetStops()
  if stops == []
     execute cmd
  endif

  const col = max([indent('.') + 1, 1])
  const old_shiftwidth = &shiftwidth

  const sw = dir == 'left' ? col - stops->FindPreviousStops(col)
                           : stops->FindNextStops(col + 1) - col
  if sw > 0
    &shiftwidth = sw
    execute cmd
    &shiftwidth = old_shiftwidth
  endif
enddef

  
export def SetShiftWidth(dir: string, use_pos: bool)
  b:word_indent_old_indentexpr = &indentexpr
  var stops = GetStops()
  if stops == []
    const vcol = getcurpos()[4]
    const  tab = vcol / &shiftwidth * &shiftwidth
    stops = [ tab - &sw, tab, tab + &sw ]
  endif

  const col = max([indent('.') + 1, 0])
  # if a line is empty use the virtual column position instead
  # to avoid going backward.
  const vcol: number = use_pos && getline('.') == '' ?  getcurpos()[4]
                                                    : col
  const sw = dir == 'left' ? stops->FindPreviousStops(vcol)  - col
                           : (stops->FindNextStops(vcol + 1) ?? (vcol + &sw)) - col
  b:word_indent_indent_shift = sw
  &indentexpr = "indent(v:lnum)+" .. string(sw)
  &indentexpr = "WordIndent#IndentShift()"
enddef


export def RestoreShiftWidth()
  &indentexpr = b:word_indent_old_indentexpr
enddef

export def IndentShift(): number
  return max([indent(v:lnum) + b:word_indent_indent_shift, 0])
enddef

export def ShiftLeft(type=''): string
  if type == ""
    &operatorfunc = ShiftLeft
    return "g@"
  endif
  normal! '[
  SetShiftWidth('left', v:false)
  normal! =']
  RestoreShiftWidth()
  return ""
enddef
export def ShiftRight(type=''): string
  if type == ""
    &operatorfunc = ShiftRight
    return "g@"
  endif
  normal! '[
  SetShiftWidth('right', v:false)
  normal! =']
  RestoreShiftWidth()
  return ""
enddef

export def SetWordStopsIf()
	if &varsofttabstop == ''
      b:word_indent_set_ = 1
		call WordIndent#SetWordStops('.')
  endif
enddef

export def UnsetWordStops()
  if get(b:, 'word_indent_set_') == 1
    set varsofttabstop= colorcolumn=
    b:word_indent_set_ = 0
  endif
enddef

export def ToggleWordStops2()
  if get(b:, 'word_indent_set_') == 1
    WordIndent#UnsetWordStops()
  else
    b:word_indent_set_ = 1
    SetWordStops('.', -1)
  endif
enddef
export def ToggleWordStops()
  const stops = GetStops()
  if stops == []
    WordIndent#SetWordStops('.', -1)
  else 
    SetCcs([])
  endif
enddef
defcompile
