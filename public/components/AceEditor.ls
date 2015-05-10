{DOM:{div}}:React = require \react
ace = require \brace
require \brace/theme/monokai
require \brace/mode/livescript
require \brace/ext/searchbox

module.exports = React.create-class {

    display-name: \AceEditor

    render: ->
        {editor-id, width, height} = @.props
        div {id: editor-id, style: {width, height}}

    component-did-mount: ->
        editor = ace.edit @.props.editor-id
            ..on \change, (, editor) ~> @.props?.on-change editor.get-value!
            ..set-options {enable-basic-autocompletion: true}
            ..set-show-print-margin false
        @.process-props {mode: \ace/mode/livescript, theme: \ace/theme/monokai} <<< @.props

    component-did-update: (prev-props) ->
        editor = ace.edit @.props.editor-id
        editor.resize! if prev-props.width * prev-props.height != @.props.width * @.props.height

    component-will-receive-props: ({editor-id, value}:props) ->
        editor = ace.edit editor-id        
        @.process-props props

    process-props: ({editor-id, mode, theme, value}:props?) ->
        editor = ace.edit editor-id
            ..get-session!.set-mode mode if !!mode
            ..set-theme theme if !!theme
        editor.set-value value if value != editor.get-value!

}