###
Basic file reader to read source code from disk.
###

fs = require('fs')

CustomSet = require('./set')
Debug = require('./debug')

module.exports =
class FileLineReader

  # TODO: check case when you're trying to get the last line of a file
  @readLineNum: (filename, lineRange, callback) ->
    stream = fs.createReadStream(filename, {
      flags: 'r',
      encoding: 'utf-8',
      fd: null,
      mode: 0o666,
      bufferSize: 64 * 1024
    })

    minLineNum = +lineRange[0]
    maxLineNum = +lineRange[1]

    fileData = ''
    stream.on('data', (data) ->
      fileData += data

      lines = fileData.split("\n")

      if lines.length >= maxLineNum
        stream.destroy()
        callback({ code: 'success', filename: filename, lineRange: lineRange, text: lines.slice(minLineNum - 1, maxLineNum) })
    )

    stream.on('error', () ->
      callback({ code: 'error', filename: filename, lineRange: lineRange, text: [] })
    )

    stream.on('end', () ->
      callback({ code: 'eof', filename: filename, lineRange: lineRange, text: [] })
    )

  @readFile: (filename) ->
    return fs.readFileSync(filename, { encoding: 'utf-8' })

  @readLineNumBatch: (readRequestArray, callback) ->
    isEqual = (obj1, obj2) ->
      return obj1[0] is obj2[0] and obj1[1][0] is obj2[1][0] and obj1[1][1] is obj2[1][1]

    fileSet = new CustomSet(isEqual)
    fileSet.add(readRequestArray)
    readRequestArray = fileSet.getContents()

    Debug.log("Sending violations off to read: ")
    Debug.log(readRequestArray)

    requests = readRequestArray.map((item) =>
      return new Promise((resolve) =>
        FileLineReader.readLineNum(item[0], item[1], resolve)
      )
    )

    Promise.all(requests).then((data) =>
      callback(data)
    )
