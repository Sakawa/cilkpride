fs = require('fs')
path = require('path')

module.exports =
class FileSync

  sftp: null
  settings: null

  constructor: (props) ->
    @getSFTP = props.getSFTP

  updateSFTP: () ->
    @getSFTP((sftp) =>
      @sftp = sftp.sftp
      @settings = sftp.settings
      console.log("[file-sync] Got a new SFTP.")
    )

  # Folder syncing

  copyFolder: (folder, localToRemote) ->
    if not @sftp
      return false

    source = @sftp
    dest = fs
    sourceBaseDir = path.join(@settings.remoteBaseDir, folder)
    messageStr = "Synced #{sourceBaseDir} to #{path.join(@settings.localBaseDir, folder)}."

    if localToRemote
      source = fs
      dest = @sftp
      sourceBaseDir = path.join(@settings.localBaseDir, folder)
      messageStr = "Synced #{sourceBaseDir} to #{path.join(@settings.remoteBaseDir, folder)}."

    (new Promise((resolve, reject) =>
      source.stat(sourceBaseDir, (err, stats) =>
        unless stats?.isDirectory()
          atom.notifications.addError("Error: Source directory #{@settings.localBaseDir} doesn't exist.")
          reject()
        else
          resolve()
      )
    )).then(() =>
      @copyFolderRecur(folder, localToRemote, source, dest, sourceBaseDir)
      atom.notifications.addSuccess(messageStr)
    )

  copyFolderRecur: (folder, localToRemote, source, dest, sourceBaseDir) ->
    (new Promise((resolve, reject) =>
      @createDestFolderIfNecessary(folder, localToRemote, resolve, reject)
    )).then(() =>
      source.readdir(sourceBaseDir, (err, files) =>
        for file in files
          newPath = null
          if localToRemote
            newPath = path.join(folder, file)
          else
            newPath = path.join(folder, file.filename)
          fullPath = path.join(sourceBaseDir, newPath)
          console.log("[file-sync] STAT :: statting #{fullPath}")
          do (newPath) =>
            source.stat(fullPath, (err, stats) =>
              throw err if err
              if stats.isFile()
                @copyFile(newPath, localToRemote)
              else if stats.isDirectory()
                @copyFolderRecur(newPath, localToRemote, source, dest, sourceBaseDir)
              else
                console.log("[file-sync] SFTP :: unknown filetype #{newPath} encountered")
            )
      )
    )

  copyFile: (file, localToRemote, callback) ->
    if not @sftp
      return false
    console.log("[file-sync STFP] :: received request for #{file} : #{localToRemote} local -> remote")
    if localToRemote
      @sftp.fastPut(path.join(@settings.localBaseDir, file), path.join(@settings.remoteBaseDir, file), (err) ->
        throw err if err
        console.log("[file-sync] SFTP :: fastPut LTR #{file} succeeded")
        callback() if callback
      )
    else
      @sftp.fastGet(path.join(@settings.remoteBaseDir, file), path.join(@settings.localBaseDir, file), (err) ->
        throw err if err
        console.log("[file-sync] SFTP :: fastPut RTL #{file} succeeded")
        callback() if callback
      )

  createDestFolderIfNecessary: (folder, localToRemote, resolve, reject) ->
    dest = fs
    destBaseDir = path.join(@settings.localBaseDir, folder)
    if localToRemote
      destBaseDir = path.join(@settings.remoteBaseDir, folder)
      dest = @sftp

    destPath = path.join(destBaseDir, folder)
    dest.stat(destPath, (err, stats) =>
      console.log("[file-sync] SFTP :: stat on #{destPath} :: isRemote #{localToRemote}")
      console.log(stats)
      if err
        dest.mkdir(destPath, (err) =>
          throw err if err
          console.log("[file-sync] SFTP :: created dest folder #{folder} :: isRemote #{localToRemote}")
          resolve()
        )
      else if not stats.isDirectory()
        throw "[file-sync] SFTP :: #{folder} exists but is not a directory :: isRemote #{localToRemote}"
      else
        console.log("[file-sync] SFTP :: verified #{folder} folder exists")
        resolve()
    )
