module.exports =
class CSVReader

  @parseCSV: (csvOutput, containsHeader) ->
    entries = csvOutput.trim().split('\n').map((line) ->
      return line.split(',').map((entry) -> return entry.trim())
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

    console.log(output)
    return output
