$ = require('jquery')
{TextEditorUtil} = require('./utils/utils')
{CompositeDisposable} = require('atom')
Debug = require('./utils/debug')

module.exports =
class PasswordView

  content: null
  passwordEditor: null
  panel: null
  subscriptions: null

  onEnter: null
  onCancel: null

  constructor: (props) ->
    Debug.log("[password-view] Password modal created")
    @subscriptions = new CompositeDisposable()
    @onEnter = props.onEnter
    @onCancel = props.onCancel # caution: these callbacks may be overwritten!
    @content = document.createElement('div')

    descriptionDiv = document.createElement('div')
    descriptionDiv.classList.add('password-view-descriptor')
    passwordPrompt = document.createElement('div')
    passwordPrompt.classList.add('password-prompt')
    passwordPrompt.textContent = "Please enter your password for "
    usernameSpan = document.createElement('span')
    usernameSpan.classList.add('username-span')
    usernameSpan.textContent = props.username
    passwordPrompt.appendChild(usernameSpan)
    disclaimerDiv = document.createElement('div')
    disclaimerDiv.classList.add('password-disclaimer')
    disclaimerDiv.textContent = "Note: The plugin will attempt to login with this password in the event of network interruptions for the rest of this session."

    descriptionDiv.appendChild(passwordPrompt)
    descriptionDiv.appendChild(disclaimerDiv)

    @content.appendChild(descriptionDiv)

    @passwordEditor = TextEditorUtil.constructTextEditor({
      mini: true
    })
    @passwordEditor.element.classList.add('password-view-editor')
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
    @subscriptions.add(atom.commands.add('atom-text-editor', 'core:confirm', () =>
      Debug.log("[password-view] Pressed enter")
      password = @passwordEditor.getText()
      @detach()
      @onEnter(password)
    ))
    @subscriptions.add(atom.commands.add('atom-text-editor', 'core:cancel', () =>
      Debug.log("[password-view] Pressed cancel")
      @detach()
      @onCancel()
    ))

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
    @subscriptions.dispose()
    @panel.destroy()

  getView: () ->
    return @content
