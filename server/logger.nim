#[
File  logger.nim
Date  2018-2-20
  2018-3-5 getGMTime -> utc
Copyright 2018 T.Teramoto
Licence MIT
]#

import strutils, times
#import threadpool

type
  #StrChannel = ptr Channel[string]
  Logger* = ref object
    #chan: StrChannel
    basename: string
    file: File
    curYear: int
    curMonth: Month

#const BaseFile= "log$1.txt"
const ExitCmd= "!EXIT!"

# global
#var chan : StrChannel
#[
proc log_loop(logger: ptr Logger) =
  echo "LOGGER started"

  while true:
    let msg= logger[].chan.recv
    if msg==ExitCmd:
      break

    if msg.len>0 and msg[0]=='*':
      echo msg
    else:
      let gmt= getTime().utc
      if gmt.month!=logger[].curMonth or gmt.year!=logger[].curYear:
        # new log file
        logger[].file.close
        let filename= BaseFile % gmt.format("yyyyMM")
        logger[].file= open(filename, fmAppend)
      let f= logger[].file
      f.writeLine(gmt.format("yyyy-MM-dd hh:mm:ss"), ",", msg)
      f.flushFile
  #end while

  echo "EXIT logger"
]#

proc log* (lg:Logger, msg:string) =
  #lg.chan.send(msg)
  if msg==ExitCmd:
    return

  if msg.len>0 and msg[0]=='*':
    echo msg
  else:
    let gmt= getTime().utc
    if gmt.month!=lg.curMonth or gmt.year!=lg.curYear:
      # new log file
      lg.file.close
      let filename= lg.basename % gmt.format("yyyyMM")
      lg.file= open(filename, fmAppend)
    let f= lg.file
    f.writeLine(gmt.format("yyyy-MM-dd hh:mm:ss"), ",", msg)
    f.flushFile

proc newLogger* (basename:string): Logger =
  #var chan: StrChannel
  #open(chan)
  let gmt= getTime().utc
  let filename= basename % gmt.format("yyyyMM")
  let f= open(filename, fmAppend)
  #result= Logger(chan: chan.addr, file: f, curYear: gmt.year, curMonth: gmt.month)
  #                     +-- chan is on the stack, so not available outside!
  #result= Logger(chan: chan, file: f, curYear: gmt.year, curMonth: gmt.month)
  #               +-- chan is copied
  result= Logger(basename:basename, file: f, curYear: gmt.year, curMonth: gmt.month)
  #spawn log_loop(result.addr)

proc closeLogger* (logger:Logger) =
  #logger.chan.send(ExitCmd)
  #sync()
  #close(logger.chan)
  logger.file.close


when isMainModule:

  var lg= newLogger("log$1.txt")
  while true:
    let ln= stdin.readLine()
    if ln=="exit":
      break
    elif ln.len==0:
      continue
    else:
      lg.log(ln)
  #end while

  lg.closeLogger

# vim: ts=2 sw=2 et
