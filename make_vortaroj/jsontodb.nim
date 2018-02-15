#[
File  jsontodb.nim
      CSV to Database
Date  2018-1-8
Compile: nim c -d:release -p:~/progs/nim jsontodb
]#

import strutils, pegs, tables
import os
import mylib/sqlite3, mylib/collate, mylib/getopts
from mylib/utils import getOr

const Vortaroj= "vortaroj.db"

type Values= array[4, string]

type DictInfo= ref object
  shortname, name: string
  version: string # version and date
  author: string
  langs: string   # eo-ja, ja-eo, eo-eo, en-eo, eo-en,...
  format: string  # plain, html
  color: string
  conv1: string
  conv2: string
  makeentry: string
  makedef: string
  schonline: string
  url: string
  remark: string

proc read_json_file(file:string): seq[Values] =
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

  # register collation
  let ret= collation_utf8_esperanto_ci(db)
  echo "create collation ret=", $ret

  # tables
  # Note: 'autoincrement' is not necessary; the primary key, 'id', is equal to ROWID
  db.exec("create table if not exists dict (id integer primary key, shortname text unique, idx integer, name text, version text, author text, langs text, format text, color text, conv1 text, conv2 text, makeentry text, makedef text, schonline text, url text, remark text)")
  db.exec("create table if not exists word (id integer primary key, dictid integer, word text collate utf8_esperanto_ci, entry text collate utf8_esperanto_ci, root text collate utf8_esperanto_ci, defid integer, subentry integer)")
  db.exec("create table if not exists def (id integer primary key, dictid integer, wordid integer, defs text collate utf8_esperanto_ci)")
  db.exec("create table if not exists disporder (dictid integer, disp integer)")

  # Indices
  db.exec("create index if not exists idxword on word (word, dictid)")
  db.exec("create index if not exists idxroot on word (root, dictid) where root!=''")

  return db

proc toLowerEsp(s:string): string {.inline.} =
  return s.multiReplace(("Ĉ","ĉ"), ("Ĝ","ĝ"), ("Ĥ","ĥ"), ("Ĵ","ĵ"), ("Ŝ","ŝ"), ("Ŭ","ŭ"))

# get a root word of Esperanto
#  remove suffixes: -a -aj -an -ajn -e -i -o -oj -on -ojn -u
#  compound words have no root; return ""
proc get_root(lang:string, word:string): string =
  proc remove_suffix(word:string): string =
    const sufs= ["a","e","i","o","u","aj","oj","an","on","ajn","ojn"]
    for suf in sufs:
      if word.endsWith(suf):
        return word[0..word.high-suf.len]
    return word

  # Begin
  if lang=="eo":
    if word.len<=2:
      return word # too short
    elif word.find(' ')>=0:
      return ""   # compound word
    else:
      let root= word.remove_suffix
      if root.contains({'a','e','i','o','u'}):
        return root
      else:
        return word # ex. 'tre'
  else:
    # not Esperanto
    return ""


proc add_vortaro_info(db:DbConn, dict:DictInfo): int =
  db.exec("insert into dict (shortname, name, version, author, langs, format, color, conv1, conv2, makeentry, makedef, schonline, url, remark) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
          dict.shortname.dbText,
          dict.name.dbText, dict.version.dbText, dict.author.dbText,
          dict.langs.dbText, dict.format.dbText, dict.color.dbText,
          dict.conv1.dbText, dict.conv2.dbText,
          dict.makeentry.dbText, dict.makedef.dbText,
          dict.schonline.dbText, dict.url.dbText,
          dict.remark.dbText)
  var row= db.fetch_one("select id from dict where shortname=?", dict.shortname.dbText)
  result= row[0].intVal  # dict ID

  # display order
  var disp= 1
  var disprow= db.fetch_one("select max(disp) from disporder")
  if disprow[0].vtype==tInt:
    disp= disprow[0].intVal + 1
  echo "index=", $disp
  db.exec("insert into disporder (dictid, disp) values (?,?)", result.dbInt, disp.dbInt)


proc add_vortoj(db:DbConn, dictid:int, langs:string, dictFile:string) =
  # prepare statements and maxIDs
  let stmt_word= db.prepare("insert into word (dictid, word, entry, root, defid, subentry) values (?,?,?,?,?,?)")
  let stmt_def = db.prepare("insert into def (dictid, wordid, defs) values (?,?,?)")
  var row= db.fetch_one("select max(id) from word")
  var maxWordId= if row[0].vtype==tNull: 0 else: row[0].intVal
  row= db.fetch_one("select max(id) from def")
  var maxDefId= if row[0].vtype==tNull: 0 else: row[0].intVal
  let db_dictid= dictid.dbInt
  #
  let data= read_json_file(dictFile)
  db.begin_transaction
  for vals in data:
    inc maxWordId
    inc maxDefId
    #var word= vals[0].multiReplace(("-",""),(".","")).toLowerAscii # remove '-', '.'
    var word= vals[0].toLowerAscii.strip(chars={'-'})  # lower Ascii, trim '-'
    if langs[0..1]=="eo":  # to lower case for Esperanto letters
       word= word.toLowerEsp
    let
      db_word= word.dbText
      db_entry= if vals[1].len>0:
                  vals[1].dbText
                elif vals[0]!=word:
                  vals[0].dbText
                else:
                  db_word
      db_root= get_root(langs[0..1], word).dbText
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

proc add_vortaro(dbfile:string, dict:DictInfo, dictFile:string) =
  let db= open_vortaroj(dbfile)
  let dictid= add_vortaro_info(db, dict)
  add_vortoj(db, dictid, dict.langs, dictFile)
  db.closeDb()


# MAIN

let help= """
Usage: jsontodb [descriptor_file] -options
Options:
 * Descriptor_file contains the following options, each on a line.
 -json:filename: Dictionary file in the JSON format
 -shortname: dictionary ID
 -name     : dictionary name
 -version  : version and/or date (default=1.0)
 -author   : (optional)
 -langs    : eo-ja,...
 -format   : plain, html,.. (default=plain)
 -color    : (optional)
 -conv1    : (optional)
 -conv2    : (optional)
 -makeentry: (optional)
 -makedef  : (optional)
 -schonline: (optional)
 -url      : (optional)
 -remark   : (optional)
 -db:DatabaseFile : (default=vortaroj.db)
"""

var (args, opts)= get_opts("", commandLineParams())
if args.len>0:
  var (_, opts2)= get_opts("", readFile(args[0]).splitLines)
  # merge
  for key,val in opts:
    opts2[key]= val
  opts= opts2

if not (opts.hasKey("json") and
        opts.hasKey("shortname") and opts.hasKey("name") and
        opts.hasKey("langs")):
  echo help

else:
  let dbfile= opts.getOr("db", Vortaroj)
  let dict= DictInfo(
          shortname: opts.getOr("shortname", "-"),
          name: opts.getOr("name", "-"),
          version: opts.getOr("version", "1.0"),
          author: opts.getOr("author", ""),
          langs: opts.getOr("langs", "**-**"),
          format: opts.getOr("format", "plain"),
          color: opts.getOr("color", ""),
          conv1: opts.getOr("conv1", "chapeligu"),
          conv2: opts.getOr("conv2", "chapeligu"),
          makeentry: opts.getOr("makeentry", "makeEntry_std"),
          makedef: opts.getOr("makedef", "makeDef_plain"),
          schonline: opts.getOr("schonline", ""),
          url: opts.getOr("url", ""),
          remark: opts.getOr("remark", ""))
  #
  echo "JSON: ", opts["json"]
  echo "shortname: ", dict.shortname
  echo "name     : ", dict.name
  echo "version  : ", dict.version
  echo "author   : ", dict.author
  echo "langs    : ", dict.langs
  echo "format   : ", dict.format
  echo "remark   : ", dict.remark
  #
  add_vortaro(dbfile, dict, opts["json"])


# vim: ts=2 sw=2 et
