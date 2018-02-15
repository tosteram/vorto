#[
File	server.nim
Date	2018-01-13
Author	T.Teramoto
Compile: nim c -d:release -p:%NimMylib% server
     or  nim c -d:release -p:~/progs/nim server
]#


import strutils, tables, os, times, browsers, json
import asyncdispatch, asynchttpserver
from nativesockets import `$`, Port

import mylib/inifile, mylib/sqlite3
import utils, httphelper #, templates


#======================================
# Constants / Module vars
#======================================
const
  StartPage= "index.html"  # start HTML
  Vortaroj = "vortaroj/vortaroj.db" # database
  IniFile  = "vortaroj.ini"
  MaxCount = 100
  OffsetLimit= 500
var
  quit_polling {.threadvar.}: bool #= false
  ini {.threadvar.}: TableRef[string,string]
  #ini_modified {.threadvar.}: bool #= false

quit_polling= false


#======================================
# Procedures
#======================================

proc get_ini_values(ini:TableRef[string,string], name: string): string =
  let val= ini[name]
  if val.find('\l')>0:
    let vals= val.split('\l')
    result= "["
    for v in vals:
      result &= "\"" & v & "\","
    result &= "]"
    result= result.replace(",]", "]")
  else:
    result= "\"" & val & "\""

proc url_to_utf8(s:string): string =
  result= newStringOfCap(s.len)
  var i= 0
  while i<s.len:
    let c= s[i]
    if c=='%':
      result.add(parseHexInt(s[i+1..i+2]).chr)
      i= i+3
    #elif c=='+':
    #  result.add(' ')
    #  inc i
    else:
      result.add(c)
      inc i

#proc open_vortaroj(): DbConn =
#  return openDb(vortaroj_db)

#proc close_vortaroj(db:DbConn) =
#  closeDb(db)


#======================================
# Routes
#======================================
#
# GET request
#
proc get_req(req: Request) {.async.} =

  echo "GET ", req.url.path #debug
  
  case req.url.path
  of "/":
    #--- Return 'StartPage'.html
    let html= readFile(StartPage)
    let headers= newHttpHeaders([("content-type", "text/html")])
    await req.respond(Http200, html, headers)

  #=== Dict Table ===

  of "/get_all_dicts":
    #--- [query]
    #    Return JSON {shortname:{id:..,name:..,version:..,author:..,langs:..,...},...}
    let
      db= openDb(Vortaroj)
      sqlstr= "select id,shortname,name,version,author,langs,format,color,conv1,conv2,makeentry,makedef,schonline,url,remark from dict"
    var ret= "{"
    for row in db.fetch_rows(sqlstr):
      let r= """"$#":{"dictid":$#,"name":"$#","version":"$#","author":"$#","langs":"$#","format":"$#","color":"$#","conv1":"$#","conv2":"$#","makeentry":"$#","makedef":"$#","schonline":"$#","url":"$#","remark":"$#"},""" %
          [row[1].textVal, $row[0].intVal, row[2].textVal, row[3].textVal,
          row[4].textVal, row[5].textVal, row[6].textVal, row[7].textVal,
          row[8].textVal, row[9].textVal, row[10].textVal, row[11].textVal,
          row[12].textVal, row[13].textVal, row[14].textVal]
      ret &= r
    #end while
    ret[ret.high]= '}'  # replace ','
    db.closeDb()

    echo ret  #debug
    await req.respond(Http200, ret)

  of "/search":
    # query : /search?dictid=xx&word=xxx
    # return: [dict_shortname, word_id, word, entry_word, def]
    let
      db= openDb(Vortaroj)
      q= get_query(req)
      sqlstr= "select shortname,word.id,word,entry,defs from word,def,dict where word=? and word.dictid=? and def.id=word.defid and dict.id=word.dictid"
      row= db.fetch_one(sqlstr, q["word"].dbText, q["dictid"].parseInt.dbInt)
      ret= if row.len==5:
             """["$#", $#, "$#", "$#", "$#"]""" %
             [row[0].textVal, $row[1].intVal, row[2].textVal, row[3].textVal,
             row[4].textVal]
           else:
             "[]"
    db.closeDb()
    echo ret  #debug
    await req.respond(Http200, ret)

  #=== Etc ===

  of "/quit":
    await req.respond(Http200, "quit")
    await sleepAsync(1000);
    quit_polling= true

  of "/host-os":
    echo hostOS # windows, macosx, linux
    await req.respond(Http200, hostOS)

  #=== Send back Files ====
  
  else:
    # Get the filename
    var filename= req.url.path.substr(1)  # remove '/'
    filename= url_to_utf8(filename) # '%hh' -> hex

    # Read/Send the file
    if fileExists(filename):
      #echo "GET ", filename
      let
        mimetype= getMimeType(filename)
        file_time= filename.getLastModificationTime
        file_time_str= file_time.getGMTime.format("ddd, d MMM yyyy hh:mm:ss 'GMT'")
      var
        status= Http200
        content: string
      let req_headers= req.headers.table
      #echo $req_headers  #debug
      let imss= req_headers.getOrDefault("if-modified-since")
                    # [weekday, day-month-year-zone]
      echo "  ims=", $imss, " file time=", file_time_str
      if imss!=nil:
        # Once accessed
        let ims= imss[1]
        #echo "ims=", ims #debug
        let time_info= ims.parse("d MMM yyyy hh:mm:ss 'GMT'")
        if time_info.toTime == file_time:
          # not modified
          echo "  not modified"
          status= Http304 #"304 Not Modified"
          content= ""
        else:
          # modified
          echo "  modified"
          content= readFile(filename)
      else:
        # The first time, Newly accessed
        echo "  reading"
        content= readFile(filename)

      let headers= newHttpHeaders([
            ("content-type", mimetype),
            ("last-modified", file_time_str)
            ])
      await req.respond(status, content, headers)

    else:
      echo "  NOT FOUND: ", filename
      await req.respond(Http404, "Error 404: Page not found.")

#
# Post request
#

proc sql_escape(s:string): string =
  return s.replace("'", "''")

proc json_escape(v:DbVal): string =
  return v.textVal
  #return v.textVal.replace("\"", "\\\"")

proc makeWhereClause(w: TableRef[string,seq[string]], match:string): string =
  # match: complete, partial, prefix, (suffix)

  proc match_cond(w:string): string =
    let pat= case match
              of "prefix": "word like '$#%'"
              of "complete": "word='$#'"
              of "partial": "word like '%$#%'"
              else: "word='$#'"   # complete match
    return pat % sql_escape(w)

  #BEGIN
  # word='WWW' and word.dictid=N or 
  # word='XXX' and (word.dictid=M1 or word.dictid=M2)
  var is_first= true
  for word, dicts in w:
    var s= match_cond(word) & " and "
    if dicts.len==1:
      # only one dict.
      s &= "word.dictid=$#" % dicts[0]
    else:
      # multiple dicts for a word
      s &= "("
      var first_dict= true
      for dictid in dicts:
        if first_dict:
          s &= "word.dictid=$#" % $dictid
          first_dict= false
        else:
          s &= " or word.dictid=$#" % $dictid
      #end for
      s &= ")"
    #end if

    if is_first:
      result= s
      is_first= false
    else:
      result &= " or " & s

# for searching defs
proc makeWhereClause2(w: TableRef[string,seq[string]], match:string): string =
  # match: word, partial

  proc match_cond(w:string): string =
    let pat= case match
              of "partial": "defs like '%$#%'"
              of "word": "defs like '%$#%'" #TODO
              else: "defs like '%$#%'"   # partial match
    return pat % sql_escape(w)

  #BEGIN
  # defs like '%WWW%' and defs.dictid=N or 
  # defs like '%XXX%' and (def.dictid=M1 or def.dictid=M2)
  var is_first= true
  for word, dicts in w:
    var s= match_cond(word) & " and "
    if dicts.len==1:
      # only one dict.
      s &= "def.dictid=$#" % dicts[0]
    else:
      # multiple dicts for a word
      s &= "("
      var first_dict= true
      for dictid in dicts:
        if first_dict:
          s &= "def.dictid=$#" % $dictid
          first_dict= false
        else:
          s &= " or def.dictid=$#" % $dictid
      #end for
      s &= ")"
    #end if

    if is_first:
      result= s
      is_first= false
    else:
      result &= " or " & s


proc post_req(req: Request) {.async.} =
  # body:
  # search_props?range=..&match=..&offset=..&sort=(lang)
  # search?word=..&dictd=..
  # ...
  echo req.body

  var props: TableRef[string,string]      #name: range,match,offset,sort
  var where= newTable[string,seq[string]]() #word, [dictid,...]

  var dict_count= 0
  for ln in req.body.splitLines:
    let
      cmd_qstr= ln.split('?')
      cmd= cmd_qstr[0]
    if cmd=="/search_props":
      props= cmd_qstr[1].query_pairs
    elif cmd=="/search":
      inc dict_count
      let
        w_d= cmd_qstr[1].query_pairs
        word= w_d["word"]
        dict= w_d["dictid"]
      if where.hasKey(word):
        where[word].add dict
      else:
        where[word]= @[dict]
  #end for

  #debug
  #echo $props
  #echo $where

  # check the limit : offet and count
  let offset= props.getOr("offset", "0").parseInt
  let maxcount= if offset+MaxCount>=OffsetLimit:
                  OffsetLimit-offset
                else:
                  MaxCount

  echo "offset=$# maxcount=$#" % [$offset, $maxcount]  #debug

  if maxcount<=0:
    await req.respond(Http200, "[]")

  elif props["range"]=="entries":
    # return JSON: [[dict_shortname, word_id, word,entry_word,def], ...]
    let db= openDb(Vortaroj)
    # select shortname,word.id,word,entry,defs from word, def, dict where 
    # (word='WWW' and word.dictid=NNN or 
    #  word='xxx' and (word.dictid=MMM1 or word.dictid=MMM2)
    # )
    # and word.dictid=dict.id and word.defid=def.id
    # TODO order by word collate utf8_esperanto_ci limit 100 offset ...
    let orderby= if dict_count>1: " order by word" else: ""
    let sqlstr="select shortname,word.id,word,entry,defs from word, def, dict where (" &
                makeWhereClause(where, props["match"]) &
                ") and word.dictid=dict.id and word.defid=def.id" & orderby &
                " limit " & $maxcount & " offset " & $offset
    echo "SQL= ", sqlstr #debug

    var ret= "["
    for row in db.fetch_rows(sqlstr):
      var str= """["$#",$#,"$#","$#","$#"],""" %
          [row[0].json_escape, $row[1].intVal, row[2].json_escape,
          row[3].json_escape, row[4].json_escape]
      ret &= str
    if ret.len==1:
      ret &= "]"          # empty
    else:
      ret[ret.high]= ']'  # replace ','
    echo "RET= ", ret #debug

    db.closeDb()

    await req.respond(Http200, ret)

  elif props["range"]=="entiretext":
    # return JSON: [[dict_shortname, word_id, word,entry_word,def], ...]
    let db= openDb(Vortaroj)
    # select shortname,word.id,word,entry,defs from word, def, dict where 
    # TODO
    # ((word is 'WWW' or entry is 'WWW' or defs like '%WWW%') and def.dictid=NNN or 
    #  ( ... defs like '%xxx%') and (def.dictid=MMM1 or def.dictid=MMM2)
    # )
    # and def.dictid=dict.id and def.id=word.defid
    # TODO order by word collate utf8_esperanto_ci limit 100 offset ...
    let orderby= if dict_count>1: " order by word" else: ""
    let sqlstr="select shortname,word.id,word,entry,defs from word, def, dict where (" &
                makeWhereClause2(where, props["match"]) &
                ") and def.dictid=dict.id and def.id=word.defid" & orderby &
                " limit " & $maxcount & " offset " & $offset
    echo "SQL= ", sqlstr #debug

    var ret= "["
    for row in db.fetch_rows(sqlstr):
      var str= """["$#",$#,"$#","$#","$#"],""" %
          [row[0].json_escape, $row[1].intVal, row[2].json_escape,
          row[3].json_escape, row[4].json_escape]
      ret &= str
    ret[ret.high]= ']'  # replace ','
    echo "RET= ", ret #debug

    db.closeDb()

    await req.respond(Http200, ret)

  else:
    discard

#
# ROUTES
#
proc routes(req: Request) {.async.} =

  case req.reqMethod
    of HttpGet:
      discard get_req(req)
    of HttpPost:
      discard post_req(req)
    else:
      discard

#======================================
# MAIN
#======================================

# Set the Current Dir
when hostOS=="macosx":
  discard # FOR TEST
  # current dir is '/'
#  const MacApp="mannyou.app"
#  let 
#    appfile= getAppFilename()
#    p= appfile.find(MacApp)
#    appdir= appfile.substr(0, p-1)
#  setCurrentDir(appdir)
else:
  # windows, (linux)
  let
    appfile= getAppFilename()
    (appdir, _)= splitPath(appfile)
  if getCurrentDir()!=appdir:
    setCurrentDir(appdir)

echo "cur.dir= ", getCurrentDir()

ini= inifile.read(IniFile)
var port= Port(ini["port"].parseInt)
var start_url= ini["start_url"]

try:
  # Start the HTTP Server
  var server= newAsyncHttpServer()
  let serveFut= server.serve(port, routes)

  echo "Server starts, listening on port ", port
  
  # Show on Browser
  if os.paramCount()>0 and os.paramStr(1)=="-n":
    discard
  else:
    openDefaultBrowser("http://localhost:" & $port & start_url)

  # Loop and finish
  while not (serveFut.finished or quit_polling):
    poll()
  # end while
  server.close
except:
  echo getCurrentExceptionMsg()

# post-process
#close_all_docs()

#if ini_modified:
#  ini.save(IniFile)

echo "[QUIT]"

# vim: ts=2 sw=2 et
