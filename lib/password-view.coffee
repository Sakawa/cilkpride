###
Password view for the popup that appears when asking for SSH password.
###

$ = require('jquery')
{CompositeDisposable} = require('atom')

Debug = require('./utils/debug')
{TextEditorUtil} = require('./utils/utils')

module.exports =
class PasswordView

  props: null             # object holding properties defined by parent class
  element: null           # top-level password div
  passwordEditor: null    # AtomTextEditor for users to type their SSH password
  panel: null             # modal panel object that the password div appears in
  subscriptions: null     # CompositeDisposable for prompt confirmation and cancellation

  onEnter: null           # function run when user submits their password
  onCancel: null          # function run when user cancels prompt (using ESC key)
                          # caution: this callback may be overwritten when SSH auths timeout

  constructor: (props) ->
    @props = props

    Debug.log("[password-view] Password modal created")
    @subscriptions = new CompositeDisposable()
    @onEnter = props.onEnter
    @onCancel = props.onCancel

    @element = document.createElement('div')

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
    @element.appendChild(descriptionDiv)

    @passwordEditor = TextEditorUtil.constructTextEditor({
      mini: true
    })
    @passwordEditor.element.classList.add('password-view-editor')
    @element.appendChild(@passwordEditor.element)

    # Password workaround for TextEditor found from
    # https://discuss.atom.io/t/password-fields-when-using-editorview-subview/11061/8
    passwordElement = $(@passwordEditor.element.rootElement)
    passwordElement.find('div.lines').addClass('password-lines')
    @passwordEditor.onDidChange(() =>
      string = @passwordEditor.getText().split('').map((() -> '*')).join('')
      passwordElement.find('#password-style').remove()
      passwordElement.append('<style id="password-style">.password-lines .line span.syntax--text:before {content:"' + string + '";}</style>')
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
    @panel ?= atom.workspace.addModalPanel(item: @element)
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
    return @element
