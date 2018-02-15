#[
File  csvtodb.nim
      CSV to Database
Date  2018-1-8
Compile: nim c -d:release -p:~/progs/nim csvtodb
]#

import strutils, pegs, tables
import os
import mylib/sqlite3, mylib/getopts

const Vortaroj= "vortaroj.db"

type Values= array[4, string]

type DictInfo= ref object
  shortname, name: string
  version: string # version and date
  author: string
  langs: string   # eo-ja, ja-eo, eo-eo, en-eo, eo-en,...
  format: string  # plain, html, (or online URL)
  remark: string

proc read_csv_file(file:string): seq[Values] =
  let f= open(file)
  # skip
  while true:
    let ln= f.readLine()
    if ln.startsWith("var "):
      break
  #
  result= newSeq[Values]()
  var m: array[4, string]
  let pattern= peg"""'["'{@}('",'' '?'"'){@}('",'' '?'"')({@}('",'' '?'"'))?{@}('"]')"""
  #let pattern= peg"""'["'{@}('",'' '?'"'){@}('",'' '?'"'){@}('"]')"""
  for ln in f.lines:
    if ln=="];":
      break
    if ln.match(pattern, m):
      result.add m
  #
  f.close()

proc open_vortaroj(dbfile:string): DbConn =
  let db= openDb(dbfile)
  # Note: 'autoincrement' is not necessary; the primary key, 'id', is equal to ROWID
  db.exec("create table if not exists dict (id integer primary key, shortname text, name text, version text, author text, langs text, format text, remark text)")
  db.exec("create table if not exists word (id integer primary key, dictid integer, word text, entry text, root text, defid integer, subentry integer)")
  db.exec("create table if not exists def (id integer primary key, dictid integer, wordid integer, defs text)")
  return db

proc get_root(lang:string, word:string): string {.inline.} =
  if lang=="eo" and
     word.len>1 and 
     word[0..word.high-1].contains({'a','e','i','o','u'}) and
     word[word.high] in {'a','e','i','o'}:
    return word[0..word.high-1]
  else:
    return word

proc add_vortaro(dbfile:string, dict:DictInfo, dictFile:string) =
  let db= open_vortaroj(dbfile)
  # Dict
  db.exec("insert into dict (shortname, name, version, author, langs, format, remark) values (?,?,?,?,?,?,?)",
          dict.shortname.dbText, dict.name.dbText,
          dict.version.dbText, dict.author.dbText,
          dict.langs.dbText, dict.format.dbText,
          dict.remark.dbText)
  var row= db.fetch_one("select id from dict where shortname=?", dict.shortname.dbText)
  let dictid= row[0].intVal
  #
  let stmt_word= db.prepare("insert into word (dictid, word, entry, root, defid, subentry) values (?,?,?,?,?,?)")
  let stmt_def = db.prepare("insert into def (dictid, wordid, defs) values (?,?,?)")
  row= db.fetch_one("select max(id) from word")
  var maxWordId= if row[0].vtype==tNull: 0 else: row[0].intVal
  row= db.fetch_one("select max(id) from def")
  var maxDefId= if row[0].vtype==tNull: 0 else: row[0].intVal
  let db_dictid= dictid.dbInt
  #
  let data= read_csv_file(dictFile)
  db.begin_transaction
  for vals in data:
    inc maxWordId
    inc maxDefId
    let
      word= vals[0]
      db_word= word.dbText
      db_entry= if vals[1].len>0: vals[1].dbText else: db_word
      db_root= get_root(dict.langs[0..1], word).dbText
      db_defid= maxDefId.dbInt
      db_subentry= dbInt(0)
    stmt_word.exec_new(db_dictid, db_word, db_entry, db_root, db_defid, db_subentry)
    let
      db_wordid= maxWordId.dbInt
      db_defs= vals[2].dbText
    stmt_def.exec_new(db_dictid, db_wordid, db_defs)

  stmt_word.finalize
  stmt_def.finalize
  db.commit
  db.closeDb()



# MAIN

let help= """
Usage: csvtodb dict_file.js -options
Options:
 -db:DatabaseFile : (default=Vortaroj.db)
 -csv:CSV    : shortname,name,version,author,langs,format,remark
 -n:Name     : dictionary name
 -s:ShortName: dict.name ID
 -v:Version  : dict. version and date
 -a:Author   : dict. author
 -r:Remark   : dict. remark
"""

let (args, opts)= get_opts("", commandLineParams())
var dict= DictInfo(shortname:"dict", name:"dict", version:"1.0", author:"",
                langs:"", format:"plain",
                remark:"")
if args.len==0:
  echo help
else:
  let dbfile= if opts.hasKey("db"): opts["db"] else: Vortaroj

  if (let csv= opts.getOrDefault("csv"); csv!=nil):
    let v= csv.split(',')
    dict.shortname= v[0]
    dict.name= v[1]
    dict.version= v[2]
    dict.author= v[3]
    dict.langs= v[4]
    dict.format= v[5]
    dict.remark= v[6]
  #if ... TODO
  #
  add_vortaro(dbfile, dict, args[0])
  #let csv= read_csv_file(paramStr(1))
  #for vs in csv:
  #  echo $vs


# vim: ts=2 sw=2 et
