###
This class is a simple set implementation that takes in a equality function
and implements a basic set interface. Note that the set does not clone
any objects, so beware when mutating objects returned from this set.
###

module.exports =
class CustomSet
  isEquals: null
  contents: null

  constructor: (isEquals) ->
    @isEquals = isEquals
    @contents = []

  add: (items, onCollide) ->
    if Array.isArray(items)
      for item in items
        @addItem(item, onCollide)
    else
      @addItem(items, onCollide)

  # onCollide allows the user to specify a way to "merge" entries if
  # they overlap.
  addItem: (item, onCollide) ->
    for elem in @contents
      if @isEquals(item, elem)
        if onCollide
          onCollide(elem, item)
        return false
    @contents.push(item)
    return true

  remove: (item) ->
    index = -1
    for i in [0 ... @contents.length]
      if @isEquals(item, @contents[i])
        index = i
        break
    return false if index is -1
    @contents.splice(index, 1)
    return true

  contains: (item) ->
    for elem in @contents
      return true if @isEquals(item, elem)
    return false

  clear: () ->
    @contents = []

  getContents: () ->
    return @contents
