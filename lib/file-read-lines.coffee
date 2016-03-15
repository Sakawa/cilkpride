fs = require('fs')

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
    index = 0
    index2 = 1
    curViolation = readRequestArray[0]
    while index < readRequestArray.length
      if index2 >= readRequestArray.length
        index += 1
        curViolation = readRequestArray[index]
        index2 = index + 1
        continue

      violation = readRequestArray[index2]
      if FileLineReader.isEqual(violation, curViolation)
        readRequestArray.splice(index2, 1)
      else
        index2 += 1

    requests = readRequestArray.map((item) =>
      return new Promise((resolve) =>
        FileLineReader.readLineNum(item[0], item[1], resolve)
      )
    )

    Promise.all(requests).then((data) =>
      callback(data)
    )

  @isEqual: (v1, v2) ->
    return v1[0] is v2[0] and v1[1][0] is v2[1][0] and v1[1][1] is v2[1][1]
