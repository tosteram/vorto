#[
File  utils.nim
Date  2017-06-24
  2018-3-5 getGMTime -> utc

Export:
  has,
  getMimeType, get_GMT
]#

import tables, os, times
from sequtils import anyIt
from strutils import parseInt

proc has* [T](es:openArray[T], t:T): bool =
  anyIt(es, it==t)
  #for e in es:
  #  if e==t: return true
  #return false

proc getMimeType* (filename: string): string =
  let MimeTbl= {
    ".txt": "text/plain",
    ".html": "text/html",
    ".xml": "text/xml",
    ".css": "text/css",
    ".js": "text/javascript", #application/javascript
    ".gif": "image/gif",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".bmp": "image/bmp",
    ".ico": "image/x-icon",
    ".pdf": "application/pdf",
    ".zip": "application/zip",
    }.newTable

  let (_,_, ext)= splitFile(filename)
  if MimeTbl.hasKey(ext):
    return MimeTbl[ext]
  else:
    return "application/octet-stream"

# -> string
proc get_GMT*(): string =
  getTime().utc.format("yyyy-MM-dd HH:mm:ss")


#-- from mylib/utils.nim

#[ ** USE getOrdefault in the strutils lib
proc getOr* [A,B](tbl: TableRef[A,B], key:A, deflt:B): B =
  try:
    tbl[key]
  except KeyError:
    deflt
]#

proc isTrue* [A](tbl: TableRef[A,string], key:A): bool =
  tbl.hasKey(key) and tbl[key]=="true"

proc toInt* [A](tbl: TableRef[A,string], key:A): int =
  try:
    return tbl[key].parseInt
  except ValueError:
    return 0

# vim: ts=2 sw=2 et
