#[
File	vortoserver.nim
Date	2018-01-13
Author	T.Teramoto
Compile: nim c -d:release -p:%NimMylib% vortoserver
     or  nim c -d:release -p:~/progs/nim --threads:on vortoserver
	     nim c -d:release -p:~/progs/nim --threads:on --deadCodeElim:off vortoserver
        (compiler bug?: --deadCodeElim:off, to load 'sqlite3.so' lib
        ( in 'release' mode on Linux Ubuntue
        ( you have to 'export LD_LIBRARY_PATH=/path/to/lib'
        (Ref. https://forum.nim-lang.org/t/2475/1
        (  or https://github.com/nim-lang/Nim/issues/2408
]#


import strutils, tables, os, times, browsers, json
import asyncdispatch, asynchttpserver
from nativesockets import `$`, Port

import mylib/inifile, mylib/sqlite3, mylib/collate
import utils, httphelper #, templates
import logger


#======================================
# Constants / Module vars
#======================================
const
  StartPage= "vorto.html"  # start HTML
  VortoDB = "vortaroj/vortaroj.db" # database
  IniFile  = "vorto.ini"
var
  quit_polling {.threadvar.}: bool #= false
  ini {.threadvar.}: TableRef[string,string]
  #dict_db {.threadvar.}: DbConn
  lg {.threadvar.}: Logger



#======================================
# Procedures
#======================================
#[
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
]#

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

proc open_vortaroj(): DbConn =
  result= openDb(VortoDB)
  let ret= collation_utf8_esperanto_ci(result)
  lg.log "*collation=" & $ret

#proc close_vortaroj(db:DbConn) =
#  closeDb(db)


#======================================
# Routes
#======================================
#
# GET request
#
proc get_req(req: Request) {.async.} =

  let msg= req.hostname & "," & "GET " & req.url.path
  lg.log "*" & msg  #debug
  lg.log msg
  
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
      db= open_vortaroj()
      sqlstr= "select id,shortname,name,version,author,langs,format,color,conv1,conv2,makeentry,makedef,schonline,url,remark from dict, disporder where dict.id=dictid and disp>0 order by disp"
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

    #echo ret  #debug
    await req.respond(Http200, ret)

  of "/search":
    # query : /search?dictid=xx&word=xxx
    # return: [dict_shortname, word_id, word, entry_word, def]
    let
      db= open_vortaroj()
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
    #echo ret  #debug
    await req.respond(Http200, ret)

  of "/close-db":
    # TODO
    await req.respond(Http400, "rejected")

  of "/reopen-db":
    # TODO
    await req.respond(Http400, "rejected")

  #=== Etc ===

  of "/quit":
    if req.hostname=="127.0.0.1" or req.hostname=="localhost":
      await req.respond(Http200, "quit")
      await sleepAsync(1000);
      quit_polling= true
    else:
      echo "/quit rejected"
      await req.respond(Http400, "rejected")

  of "/host-os":
    #lg.log "*" & hostOS # windows, macosx, linux
    await req.respond(Http200, hostOS)

  #=== Send back Files ====
  
  else:
    # Get the filename
    var filename= req.url.path.substr(1)  # remove '/'
    filename= url_to_utf8(filename) # '%hh' -> hex

    # TODO SECURITY HOLE!
    # reject filename containing ".."

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
      lg.log "*  ims=" & $imss & " file time=" & file_time_str
      if imss!=nil:
        # Once accessed
        let ims= imss[1]
        #echo "ims=", ims #debug
        let time_info= ims.parse("d MMM yyyy hh:mm:ss 'GMT'")
        if time_info.toTime == file_time:
          # not modified
          lg.log "*  not modified"
          status= Http304 #"304 Not Modified"
          content= ""
        else:
          # modified
          lg.log "*  modified"
          content= readFile(filename)
      else:
        # The first time, Newly accessed
        lg.log "*  reading"
        content= readFile(filename)

      let headers= newHttpHeaders([
            ("content-type", mimetype),
            ("last-modified", file_time_str)
            ])
      await req.respond(status, content, headers)

    else:
      lg.log "*  NOT FOUND: " & filename
      await req.respond(Http404, "Error 404: Page/File not found.")

#
# Post request
#

proc sql_escape(s:string): string =
  return s.replace("'", "''")

proc json_escape(v:DbVal): string {.inline.} =
  return v.textVal
  #return v.textVal.replace("\"", "\\\"")

# for searching word
# match: prefix,complete, partial
proc makeClause_word(w: TableRef[string,seq[string]], match:string): string =
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

# for searching root
# match: complete (only)
proc makeClause_root(w: TableRef[string,seq[string]], match:string): string =
  # root='WWW' and word.dictid=N or 
  # root='XXX' and (word.dictid=M1 or word.dictid=M2)
  var is_first= true
  for word, dicts in w:
    var s= "root='$#' and " % sql_escape(word)
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
  #end for

# for searching defs
# match: paritial(always for defs), word(only for the 'word' and 'entry' fields)
proc makeClause_text(w: TableRef[string,seq[string]], match:string): string =

  proc match_cond(w:string): string =
    let pat= case match
              of "word": "(word='$1' or entry='$1' or defs like '%$1%')"
              else: "(word like '%$1%' or entry like '%$1%' or defs like '%$1%')" #partial
    return pat % sql_escape(w)

  #BEGIN
  # (word=... or entry=... or defs like '%WWW%') and defs.dictid=N or 
  # (word... or entry... or defs like '%XXX%') and (def.dictid=M1 or def.dictid=M2)
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
  lg.log "*" & req.body
  lg.log req.hostname & "," & "POST " & req.url.path

  if not req.body.startsWith("/search"):
    await req.respond(Http400, "rejected")
    return

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
  var msg= "SEARCH," & props["range"] & "," & props["match"] & ","
  for wd,ids in where:
    msg &= wd & ":"
    for id in ids:
      msg &= $id & " "
    msg[msg.high]= ','
  msg.setLen(msg.len-1) #remove the last ','
  lg.log msg

  # check the limit : offet and count
  let offset= props.getOr("offset", "0").parseInt
  let limit = props.getOr("limit", "0").parseInt
  lg.log "*offset=$# limit=$#" % [$offset, $limit]  #debug

  if props["range"]=="entries":
    # return JSON: [[dict_shortname, word_id, word,entry_word,def], ...]
    let db= open_vortaroj()
    # select shortname,word.id,word,entry,defs from word, def, dict where 
    # (word='WWW' and word.dictid=NNN or 
    #  word='xxx' and (word.dictid=MMM1 or word.dictid=MMM2)
    # )
    # and word.dictid=dict.id and word.defid=def.id
    # order by word collate utf8_esperanto_ci limit 100 offset ...
    let orderby= if dict_count>1: " order by word" else: ""
    let sqlstr="select shortname,word.id,word,entry,defs from word, def, dict where (" &
                makeClause_word(where, props["match"]) &
                ") and word.dictid=dict.id and word.defid=def.id" & orderby &
                " limit " & $limit & " offset " & $offset
    lg.log "*SQL= " & sqlstr #debug

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
    #echo "RET= ", ret #debug

    db.closeDb()

    await req.respond(Http200, ret)

  elif props["range"]=="entiretext":
    # return JSON: [[dict_shortname, word_id, word,entry_word,def], ...]
    let db= open_vortaroj()
    # select shortname,word.id,word,entry,defs from word, def, dict where 
    # TODO
    # ((word is 'WWW' or entry is 'WWW' or defs like '%WWW%') and def.dictid=NNN or 
    #  ( ... defs like '%xxx%') and (def.dictid=MMM1 or def.dictid=MMM2)
    # )
    # and def.dictid=dict.id and def.id=word.defid
    # order by word collate utf8_esperanto_ci limit 100 offset ...
    let orderby= if dict_count>1: " order by word" else: ""
    let sqlstr="select shortname,word.id,word,entry,defs from word, def, dict where (" &
                makeClause_text(where, props["match"]) &
                ") and def.dictid=dict.id and def.id=word.defid" & orderby &
                " limit " & $limit & " offset " & $offset
    lg.log "*SQL= " & sqlstr #debug

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
    #echo "RET= ", ret #debug

    db.closeDb()

    await req.respond(Http200, ret)

  elif props["range"]=="root":
    # return JSON: [[dict_shortname, word_id, word,entry_word,def], ...]
    let db= open_vortaroj()
    # select shortname,word.id,word,entry,root,defs from word, def, dict where 
    # (root='WWW' and word.dictid=NNN or 
    #  root='xxx' and (word.dictid=MMM1 or word.dictid=MMM2)
    # )
    # and word.dictid=dict.id and word.defid=def.id
    let orderby= "" #if dict_count>1: " order by root" else: ""
    let sqlstr="select shortname,word.id,word,entry,defs from word,def,dict where (" &
                makeClause_root(where, props["match"]) &
                ") and word.dictid=dict.id and word.defid=def.id" & orderby &
                " limit " & $limit & " offset " & $offset
    lg.log "*SQL= " & sqlstr #debug

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
    #echo "RET= ", ret #debug

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
      await req.respond(Http405, "That method not allowed")

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

lg= newLogger()

try:
  # Start the HTTP Server
  var server= newAsyncHttpServer()
  let serveFut= server.serve(port, routes)
  echo "Server starts, listening on port ", port

  # Open database
  #dict_db = open_vortaroj()

  # Show on Browser
  if hostOS=="linux" or os.paramCount()>0 and os.paramStr(1)=="-n":
    discard
  else:
    openDefaultBrowser("http://localhost:" & $port & start_url)

  # Loop and finish
  quit_polling= false
  while not (serveFut.finished or quit_polling):
    poll()

  # finished
  #dict_db.closeDb()
  server.close
except:
  echo getCurrentExceptionMsg()

# post-process
lg.log "QUIT"
closeLogger lg

echo "[QUIT]"

# vim: ts=2 sw=2 et
