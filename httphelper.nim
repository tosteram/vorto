#[
File	httphelper.nim
Date	2017-04-25
]#

import asynchttpserver
import strutils, tables

proc decode_url(s: string): string =
  result= ""
  var i= 0
  while i<s.len:
    let c= s[i]
    inc i
    if c=='+':
      result.add(' ')
    elif c=='%':
      if i+1<s.len:
        result.add( parseHexInt(s[i..i+1]).chr )
        i += 2
      else:
        result.add(c)
    else:
      result.add(c)

# qstr: "name1=val1&name2=val2..."
proc query_pairs* (qstr:string): TableRef[string,string] =
  result= newTable[string,string]()
  let qs= split(qstr, '&')
  for q in qs:
    let nv= q.split('=')
    result[nv[0]]= nv[1].decode_url

# req.reqMethod, req.url.path, query, req.headers[], req.body

proc get_query* (req: Request): TableRef[string,string] =
  let qstr= if req.url.query.len>0:
              req.url.query
            elif req.reqMethod==HttpPost and 
                req.headers["content-type"].contains("application/x-www-form-urlencoded"):
              req.body
            else:
              ""
  return query_pairs(qstr)

#[
proc callback(req: Request) {.async.} =
  case req.url.path
  of "/":
    await req.respond(Http200, "<h1>Hello, this is The ROOT.</h1>")
  of ...
  else: ...

var server= newAsyncHttpServer()
waitFor server.serve(Port(5000), callback)
]#

# vim: ts=2 sw=2 et
