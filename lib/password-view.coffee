$ = require('jquery')
{TextEditorUtil} = require('./utils/utils')

module.exports =
class PasswordView

  content = null
  passwordEditor: null
  panel: null

  constructor: (description, onEnter, onCancel) ->
    console.log("[password-view] Password modal created")
    @content = document.createElement('div')
    if description
      descriptionDiv = document.createElement('div')
      descriptionDiv.classList.add('password-view-descriptor')
      descriptionDiv.textContent = description
      @content.appendChild(descriptionDiv)

    @passwordEditor = TextEditorUtil.constructTextEditor({
      mini: true
    })
    @content.appendChild(@passwordEditor.element)

    # Password workaround for TextEditor found from
    # https://discuss.atom.io/t/password-fields-when-using-editorview-subview/11061/8
    passwordElement = $(@passwordEditor.element.rootElement)
    passwordElement.find('div.lines').addClass('password-lines')
    @passwordEditor.onDidChange(() =>
      string = @passwordEditor.getText().split('').map((() -> '*')).join('')
      passwordElement.find('#password-style').remove()
      passwordElement.append('<style id="password-style">.password-lines .line span.text:before {content:"' + string + '";}</style>')
    )
    atom.commands.add('atom-text-editor', 'core:confirm', () =>
      console.log("[password-view] Pressed enter")
      console.log("Your password is #{@passwordEditor.getText()}")
      password = @passwordEditor.getText()
      @detach()
      onEnter(password)
    )
    atom.commands.add('atom-text-editor', 'core:cancel', () =>
      console.log("[password-view] Pressed cancel")
      @detach()
      onCancel()
    )

    @attach()

  attach: () ->
    @panel ?= atom.workspace.addModalPanel(item: @content)
    @panel.show()
    $(@passwordEditor.element).focus()
    $(@passwordEditor.element).blur(() ->
      this.focus()
    )

  detach: () ->
    @passwordEditor.setText('')
    $(@passwordEditor.element).off("blur")
    @panel.destroy()

  getView: () ->
    return @content
