#[
File template.nim
Date 2017-04-20
Author TTeramoto
]#

import tables
from pegs import nil

#----------------------------
# Template
#----------------------------
proc fill_template* (tmpl: string, params:TableRef[string,string]): string =
  let ptn= pegs.peg"'{{'{@}'}}'"
  result= ""
  var m: array[1, string]
  var pos= 0
  while true:
    let (fst, snd)= pegs.findBounds(tmpl, ptn, m, pos)
    if fst>=0:
      if fst>pos:
        result &= tmpl.substr(pos, fst-1)
      try:
        result &= params[m[0]]
      except ValueError:
        discard
      pos= snd+1
    else:
      result &= tmpl.substr(pos)
      break
  #end while

proc fill_template_file* (file:string, params:TableRef[string,string]): string =
  return fill_template(file.readFile, params)

# vim: ts=2 sw=2 et
