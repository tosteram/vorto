#[
File	vortoserver.nim
Date	2018-01-13
Author	T.Teramoto
Compile: nim c -d:release -p:%NimMylib% vortoserver
     or  nim c -d:release -p:~/progs/nim --threads:on vortoserver
	     nim c -d:release -p:~/progs/nim --threads:on vortoserver
        (compiler bug?: --deadCodeElim:off, to load 'sqlite3.so' lib)
        ( in 'release' mode on Linux Ubuntue
        ( you have to 'export LD_LIBRARY_PATH=/path/to/lib'
        (Ref. https://forum.nim-lang.org/t/2475/1
        (  or https://github.com/nim-lang/Nim/issues/2408
]#


import strutils, tables, os, times, browsers, json
import asyncdispatch, asynchttpserver
from asyncnet import close  #close asyncSocket
from nativesockets import `$`, Port
import osproc

import mylib/inifile, mylib/sqlite3, mylib/collate
import utils, httphelper, templates
import logger


#======================================
# Constants / Module vars
#======================================
const
  RootPage= "index.html"  # start HTML
  VortoDB = "server/vortaroj/vortaroj.db" # database
  IniFile  = "vorto.ini"
  ErrorPage404= "The file can be found in the room No. 404."
type StrTable= TableRef[string,string]
var
  quit_polling {.threadvar.}: bool #= false
  ini {.threadvar.}: StrTable
  existingDirs {.threadvar.}: StrTable
  #dict_db {.threadvar.}: DbConn
  lg {.threadvar.}: Logger
  WebHome {.threadvar.}: string


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

# [in]str: "name1=val1[LF]name2=val2..."
proc getTable(str:string): StrTable =
  result= newTable[string,string]()
  for nameval in str.split('\n'):
    let pair= nameval.split('=')
    result[pair[0]]= pair[1]

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

proc matchDir(filename:string): string {.inline.} =
  existingDirs.getOrDefault(filename)

proc sendFile(req:Request, filename:string) {.async.} =
      #echo "GET ", filename
      let
        mimetype= getMimeType(filename)
        file_time= filename.getLastModificationTime
        file_time_str= file_time.utc.format("ddd, d MMM yyyy hh:mm:ss 'GMT'")
      var
        status= Http200
        content: string
      let req_headers= req.headers.table
      #echo $req_headers  #debug
      let imss= req_headers.getOrDefault("if-modified-since")
                    # [weekday, day-month-year-zone]
      lg.log "*  ims=" & $imss & " file time=" & file_time_str
      if imss.len>0:
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

#prog: __.pl or __.py
proc callCgi(req:Request, prog:string) {.async.} =
  let p= startProcess(prog, options={})
  var inF, outF: File
  discard open(inF, p.outputHandle, fmRead)   # handle to File
  discard open(outF, p.inputHandle, fmWrite)  # "

  #let querystr= url_to_utf8(req.url.query)
  let line= "GET /?" & req.url.query & " HTTP/1.0"
  lg.log "* (CGI) " & line  #debug
  outF.writeLine line
  outF.flushFile  # IMPORTANT! Needed
  let resp= inF.readAll # headers + empty_line + body
  discard p.waitForExit
  p.close

  let pos= resp.find("\r\n\r\n")
  if pos>=0:
    let body= resp.substr(pos+4)
    lg.log "* (response) " & body  #debug
    # TODO temporary
    #let headerBlock= resp[0..<pos]
    let headers= newHttpHeaders([("content-type", "text/html")])
    await req.respond(Http200, body, headers)
  else:
    await req.respond(Http500, "CGI Process Error")

func toVer(version:string): int =
  for v in version.split('.'):
    result= (result shl 8) + v.parseInt

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
    #--- Return /index.html
    let html= readFile(WebHome / RootPage)
    let headers= newHttpHeaders([("content-type", "text/html")])
    await req.respond(Http200, html, headers)

  #=== /vorto ===

  of "/vorto/get_all_dicts":
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

  of "/vorto/search":
    # query : /search?dictid=xx&word=xxx
    # return: [dict_shortname, word_id, word, entry_word, def]
    let q= get_query(req)
    if not (q.hasKey("word") and q.hasKey("dictid")):
      await req.respond(Http200, "[]")
      return

    let
      db= open_vortaroj()
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
    lg.log req.hostname & ",SCH," & q["word"] & ":" & q["dictid"]
    await req.respond(Http200, ret)

  of "/vorto/close-db":
    # TODO
    await req.respond(Http400, "rejected")

  of "/vorto/reopen-db":
    # TODO
    await req.respond(Http400, "rejected")

  #=== Foliaro ===

  of "/foliaro/checkforupdates":
    let
      q= get_query(req)
      lang= q["lang"]  # ja, en
      ini= inifile.read(WebHome / "foliaro/checkforupdates.ini")
      user_version= q["version"]
      latest_version= ini["latest_version"]
      tbl= {"lang": lang,
            "disp_en": if lang=="ja": "none" else:"block",
            "disp_ja": if lang=="ja": "block" else:"none",
            "user_version": user_version,
            "latest_version": latest_version,
            "version_date": ini["version_date"],
            "download_url": if lang=="ja": ini["download_url"]
                            else: ini["download_url_en"],
            "date": ini["date"] }.newTable
      file= if user_version.toVer < latest_version.toVer:
              # new version available
              WebHome/"foliaro/newversion.htmlt"
            else:
              # up to date
              WebHome/"foliaro/uptodate.htmlt"
      html= fill_template_file(file, tbl)
      headers= newHttpHeaders([("content-type", "text/html")])
    await req.respond(Http200, html, headers)

  #=== Etc ===

  of "/quit":
    if req.hostname=="127.0.0.1" or req.hostname=="localhost":
      await req.respond(Http200, "quit")
      await sleepAsync(1000);
      quit_polling= true
    else:
      lg.log "*/quit rejected"
      await req.respond(Http400, "rejected")

  of "/host-os":
    #lg.log "*" & hostOS # windows, macosx, linux
    await req.respond(Http200, hostOS)

  #=== Send back Files / CGI ====

  else:
    var filename= url_to_utf8(req.url.path)   # '%hh'->hex

    #== Defined Directory?
    if filename[^1]=='/' and
       (let indexfile= matchDir(filename); indexfile.len>0):
      let html= readFile(indexfile)
      let headers= newHttpHeaders([("content-type", "text/html")])
      await req.respond(Http200, html, headers)
      return
      
    # Get the filename
    filename= filename.substr(1)  # remove the top '/'

    # reject filename containing ".."
    if filename[0]=='.' or filename.contains(".."):
      lg.log "*  PATH ERROR"
      await req.respond(Http404, ErrorPage404)
      return

    # set filename under the WebHome
    filename= WebHome / filename

    if filename.endsWith(".php"):
      req.client.close
      lg.log "* disconnected: " & filename
      #await req.respond(Http200, "You've got money, Lucky man!")
      return

    # Read/Send the file
    if fileExists(filename):
      let (_, _, ext)= splitFile(filename)
      let prog= case ext
                of ".pl": "perl"
                of ".py": "python"
                else: ""
      if prog.len>0:
        discard callCgi(req, filename)
      else:
        discard sendFile(req, filename)

    else:
      lg.log "*  NOT FOUND: " & filename
      await req.respond(Http404, ErrorPage404)

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

  if req.url.path != "/vorto/search":
    lg.log req.hostname & "," & "POST " & req.url.path & " - bad path"
    await req.respond(Http400, "rejected")
    return

  lg.log "*" & req.body

  var props: TableRef[string,string]      #name: range,match,offset,sort
  var where= newTable[string,seq[string]]() #word, [dictid,...]

  var dict_count= 0
  for ln in req.body.splitLines:
    if ln.len==0: continue
    let
      cmd_qstr= ln.split('?')
      cmd= cmd_qstr[0]
    if cmd=="/search_props":
      props= cmd_qstr[1].query_pairs
    elif cmd=="/search":
      inc dict_count
      let
        w_d= cmd_qstr[1].query_pairs
        word= w_d.getOrDefault("word")
        dict= w_d.getOrDefault("dictid")
      if word.len==0 or dict.len==0:
        continue
      if where.hasKey(word):
        where[word].add dict
      else:
        where[word]= @[dict]
    #else: discard
  #end for

  if not(props.hasKey("range") and props.hasKey("match") and where.len>0):
    await req.respond(Http200, "[]")
    return

  #debug
  #echo $props
  #echo $where
  var msg= req.hostname & ",SEARCH," & props["range"] & "," & props["match"] & ","
  for wd,ids in where:
    msg &= wd & ":"
    for id in ids:
      msg &= $id & " "
    msg[msg.high]= ','
  msg.setLen(msg.len-1) #remove the last ','
  lg.log msg

  # check the limit : offet and count
  let offset= props.getOrDefault("offset", "0").parseInt
  let limit = props.getOrDefault("limit", "0").parseInt
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
    # range error
    await req.respond(Http200, "[]")

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

let (appdir, _)= getAppFilename().splitPath # vortoserver in 'server' dir
ini= inifile.read(appdir / IniFile)

setCurrentDir(appdir / ini["cur_dir"])
echo "cur.dir= ", getCurrentDir()
WebHome= ini["web_home"]
existingDirs= getTable(ini["dirs"])

lg= newLogger(ini["log_file"])

try:
  # Start the HTTP Server
  let port= Port(ini["port"].parseInt)
  var server= newAsyncHttpServer()
  let serveFut= server.serve(port, routes)
  lg.log "[Server starts]"
  lg.log "*Server starts, listening on port " & $port

  # Open database
  #dict_db = open_vortaroj()

  # Show on Browser
  if hostOS=="linux" or os.paramCount()>0 and os.paramStr(1)=="-n":
    discard
  else:
    openDefaultBrowser("http://localhost:" & $port & ini["start_url"])

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
lg.log "[QUIT]"
lg.log "*[QUIT]"
closeLogger lg

# vim: ts=2 sw=2 et
