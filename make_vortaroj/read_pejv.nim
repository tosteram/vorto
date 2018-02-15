#File  read_pejv.nim
#Date  2018-2-13

import strutils, pegs
from algorithm import sort
from encodings import nil

type Values= array[4, string]

proc toLower(s:string): string =
  return s.toLowerAscii.multiReplace(
          ("Ĉ","ĉ"), ("Ĝ","ĝ"), ("Ĥ","ĥ"), ("Ĵ","ĵ"), ("Ŝ","ŝ"), ("Ŭ","ŭ"))

proc read_pejv_file*(file:string): seq[Values] =
  proc chapeligu(s:string): string =
    s.multiReplace(
          ("c^","ĉ"), ("g^","ĝ"), ("h^","ĥ"), ("j^","ĵ"), ("s^","ŝ"), ("u^","ŭ"),
          ("C^","Ĉ"), ("G^","Ĝ"), ("H^","Ĥ"), ("J^","Ĵ"), ("S^","Ŝ"), ("U^","Ŭ"))

  result= newSeq[Values]()
  let encode= encodings.open("UTF-8", "shift_jis")
  defer: encodings.close(encode)
  let pat= peg"{@}':'{('{'@'}')?}{.*}"
  var m: array[3, string]
  for ln in file.lines:
    let ln1= encodings.convert(encode, ln)
    if ln1.match(pat, m):
      let entry= m[0].chapeligu
      let word= entry.strip(chars={'-'}).replace("/").toLower # remove '/', trim '-'
      let remark= m[1].strip(chars={'{','}'}) # m[1] may be empty
      let def= m[2].chapeligu
      result.add [word, entry, def, remark]

proc json_escape(s:string): string {.inline.} =
  return s.replace("\"", "\\\"")

proc cmp_esp(a,b:string): int =
  proc conv(s:string): string=
    s.multiReplace(
          ("ĉ","c~"), ("ĝ","g~"), ("ĥ","h~"), ("ĵ","j~"), ("ŝ","s~"), ("ŭ","u~"))
  # a,b are already in lower case
  cmp(a.conv, b.conv)

proc pejv_to_json*(file:string, outfile:string, head:string) =
  let outf= open(outfile, fmWrite)
  outf.writeLine(head)
  outf.writeLine("var pejvDict=[")
  var entries= read_pejv_file(file)
  entries.sort do (a,b:Values) -> int: cmp_esp(a[0],b[0])
  for e in entries:
    outf.writeLine """["$1","$2","$3","$4"],""" %
        [e[0], if e[0]==e[1]:"" else:e[1], e[2].json_escape, e[3]]
  outf.writeLine "];"
  outf.close


when isMainModule:
  let PejvText= "pejv181/pejvo.txt"
  let PejvJS  = "pejv181/pejv.js"

  pejv_to_json(PejvText, PejvJS, "//v1.81 2017-01-30")

# vim: ts=s sw=2 et
