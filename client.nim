

import strutils, os
import httpclient

let Host= "localhost"
let Port= "8080"
let Quit= "/quit"

let help="""
Usage: client [-options]
Options:
  -h:HOST  default=localhost
  -p:PORT  default=8080
  -c:Path  default=/quit
  -?       Help
"""

var host= Host
var port= Port
var cmd = Quit
for p in commandLineParams():
  if p.startsWith("-h"):
    host= p.substr(3)
  elif p.startsWith("-p"):
    port= p.substr(3)
  elif p.startsWith("-c"):
    cmd= p.substr(3)
  else:
    echo help
    quit()

let get_cmd= "http://" & host & ":" & port & cmd
echo "Sending : ", get_cmd
var client= newHttpClient()
echo "Received: ", client.getContent(get_cmd)

# vim: ts=2 sw=2 et
