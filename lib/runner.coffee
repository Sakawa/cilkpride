extend = require('util')._extend;
process = require('process')
SSHModule = require('./ssh-module')
spawn = require('child_process').spawn

module.exports =
class Runner

  sshModule: null
  sshEnabled: false
  settings: null

  constructor: (sshEnabled, sshModule, settings) ->
    @sshEnabled = sshEnabled
    @sshModule = sshModule
    @settings = settings

  spawn: (command, args, options) ->
    if sshEnabled:
      sshModule.spawn(command, args, options, callback)
    else:
      thread = spawn(command, @getConfSettings(false).commandArgs, {env: envCopy})
      callback(thread)

  kill: (childProcess) ->
    toClass = {}.toString
    objectClass = toClass.call(childProcess)
    console.log("[runner] trying to kill #{toClass.call(childProcess)}")

    if objectClass is "[object Thread]"
      childProcess.kill('SIGKILL')
    else if objectClass is "[object Instance]"
      childProcess.end()
