Debug = require('./debug')

module.exports =
class CSVReader

  @parseCSV: (csvOutput, containsHeader) ->
    entries = csvOutput.trim().split('\n').map((line) ->
      return line.split(',').map((entry) ->
        output = entry.trim()
        if output[0] is '"'
          output = output.substring(1)
        if output[output.length - 1] is '"'
          output = output.substring(0, output.length - 1)
        if output isnt "-nan"
          return output
        else
          return "Infinity"
      )
    )

    output = []
    if containsHeader
      headers = entries[0]
      for i in [1...entries.length]
        item = {}
        for j in [0...entries[i].length]
            item[headers[j]] = entries[i][j]
        output.push(item)
    else
      output = entries

    Debug.log(output)
    return output
