ace-language-tools = require \brace/ext/language_tools 
require! \../client-storage.ls
window.d3 = require \d3
$ = require \jquery-browserify
{key} = require \keymaster
require! \notifyjs
{all, any, camelize, concat-map, dasherize, difference, each, filter, find, keys, is-type, 
last, map, sort-by, sum, round, obj-to-pairs, pairs-to-obj, take, unique, unique-by} = require \prelude-ls
presentation-context = require \../presentation/context.ls
transformation-context = require \../transformation/context.ls
{cancel-event, compile-and-execute-livescript, compile-and-execute-javascript, generate-uid, 
is-equal-to-object, get-all-keys-recursively} = require \../utils.ls
_ = require \underscore
{create-factory, DOM:{a, div, input, label, span, select, option, button, script}}:React = require \react
{Navigation} = require \react-router
AceEditor = create-factory require \./AceEditor.ls
ConflictDialog = create-factory require \./ConflictDialog.ls
DataSourceCuePopup = create-factory require \./DataSourceCuePopup.ls
Menu = create-factory require \./Menu.ls
ReactSelectize = create-factory require \react-selectize
SettingsDialog = create-factory require \./SettingsDialog.ls
SharePopup = create-factory require \./SharePopup.ls
ui-protocol =
    mongodb: require \../query-types/mongodb/ui-protocol.ls
    mssql: require \../query-types/mssql/ui-protocol.ls
    multi: require \../query-types/multi/ui-protocol.ls
    curl: require \../query-types/curl/ui-protocol.ls
    postgresql: require \../query-types/postgresql/ui-protocol.ls
    mysql: require \../query-types/mysql/ui-protocol.ls

# trace :: a -> b -> b
trace = (a, b) --> console.log a; b

# trace-it :: a -> a
trace-it = (a) -> console.log a; a

# returns dasherized collection of keywords for auto-completion
keywords-from-object = (object) ->
    object
        |> keys 
        |> map dasherize

# takes a collection of keywords & maps them to {name, value, score, meta}
convert-to-ace-keywords = (keywords, meta, prefix) ->
    keywords
        |> map -> {text: it, meta}
        |> filter -> (it.text.index-of prefix) == 0 
        |> map ({text, meta}) -> {name: text, value: text, score: 0, meta}

alphabet = [String.from-char-code i for i in [65 to 65+25] ++ [97 to 97+25]]

# returns a hash of editor-heights used in get-initial-state and state-from-document
# editor-heights :: Integer?, Integer?, Integer? -> {query-editor-height, transformation-editor-height, presentation-editor-height}
editor-heights = (query-editor-height = 300, transformation-editor-height = 324, presentation-editor-height = 240) ->
    # 50 = height of .menu defined in Meny.styl; 30 = height of .editor-title;
    viewport-height = window.inner-height - 50 - 3 * 30
    editor-heights = [query-editor-height, transformation-editor-height, presentation-editor-height] |> (ds) ->
        s = sum ds
        ds |> map round . (viewport-height *) . (/s)
    query-editor-height: editor-heights.0
    transformation-editor-height: editor-heights.1
    presentation-editor-height: editor-heights.2

module.exports = React.create-class do

    display-name: \QueryRoute

    mixins: [Navigation]

    # React class method
    # render :: a -> VirtualDOM
    render: ->
        {
            query-id, branch-id, tree-id, data-source-cue, query, query-title, 
            transformation, presentation, parameters, existing-tags, tags, editor-width, 
            popup-left, popup, queries-in-between, dialog, remote-document, cache,  
            from-cache, executing-op, displayed-on, execution-error, execution-end-time, 
            execution-duration
        } = @state

        # MENU ITEMS
        toggle-popup = (popup-name, button-left, button-width) ~~>
            @set-state do
                popup-left: button-left + button-width / 2
                popup: if @state.popup == popup-name then '' else popup-name

        saved-query = !!@props.params.branch-id and !(@props.params.branch-id in <[local localFork]>) and !!@props.params.query-id

        menu-items = 
            * label: \New, icon: \n, action: ~> window.open "/branches", \_blank
            * label: \Fork
              icon: \f
              enabled: saved-query
              action: ~> 
                  # throw an error if the document cannot be forked (i.e when the branch id is already local or localFork)
                  {query-id, parent-id, tree-id, query-title}:document? = @document-from-state!
                  throw "cannot fork a local query, please save the query before forking it" if @props.params.branch-id in <[local localFork]>

                  # create a new copy of the document, update as required then save it to local storage
                  {query-id}:forked-document = {} <<< document <<< {
                      query-id: generate-uid!
                      parent-id: query-id
                      branch-id: \localFork
                      tree-id
                      query-title: "Copy of #{query-title}"
                  }
                  client-storage.save-document query-id, forked-document

                  # by redirecting the user to a localFork branch we cause the document to be loaded from local-storage
                  window.open "/branches/localFork/queries/#{query-id}", \_blank
            * label: \Save, hotkey: "command + s", icon: \s, action: ~> @save!
            * label: \Cache
              icon: \c
              highlight: if from-cache then 'rgba(0,255,0,1)' else null
              toggled: cache
              type: \toggle
              action: ~> @set-state {cache: !cache}
            * label: \Execute
              icon: \e
              enabled: data-source-cue.complete
              hotkey: "command + enter"
              show: !executing-op
              action: ~> @execute!
            * label: \Cancel
              icon: \ca
              show: !!executing-op
              action: ~> $.get "/apis/ops/#{executing-op}/cancel"
            * label: 'Data Source'
              icon: \d
              pressed: \data-source-cue-popup == popup
              action: toggle-popup \data-source-cue-popup
            * label: \Parameters
              icon: \p
              pressed: \parameters-popup == popup
              action: toggle-popup \parameters-popup
            * label: \Tags
              icon: \t
              pressed: \tags-popup == popup
              action: toggle-popup \tags-popup
            * label: \Reset
              icon: \r
              enabled: saved-query
              action: ~> 
                <~ @set-state (@state-from-document remote-document)
                @save-to-client-storage!
            * label: \Diff
              icon: \t
              enabled: saved-query
              highlight: do ~>
                return null if !saved-query
                changes = @changes-made!
                return null if changes.length == 0
                return 'rgba(0,255,0,1)' if changes.length == 1 and changes.0 == \parameters
                'rgba(255,255,0,1)'
              action: ~> window.open "#{window.location.href}/diff", \_blank
            * label: \Share
              icon: \h
              enabled: saved-query
              pressed: \share-popup == popup
              action: toggle-popup \share-popup
            * label: \Snapshot
              icon: \s
              enabled:saved-query
              action: ~>
                  {branch-id, query-id}:saved-document <~ @save
                  $.get "/apis/branches/#{branch-id}/queries/#{query-id}/export/#{@state.cache}/png/1200/800?snapshot=true"
            * label: \VCS, icon: \v, enabled: saved-query, action: ~> window.open "#{window.location.href}/tree", \_blank
            * icon: \t, label: \Settings, enabled: true, action: (button-left) ~> @set-state {dialog: \settings}


        div {class-name: \query-route},

            # MENU
            Menu do 
                ref: \menu
                items: menu-items 
                    |> filter ({show}) -> (typeof show == \undefined) or show
                    |> map ({enabled}:item) -> {} <<< item <<< {enabled: (if typeof enabled == \undefined then true else enabled)}
                a class-name: \logo, href: \/

            # POPUPS

            # left-from-width :: Number -> Number
            left-from-width = (width) ~>
                x = popup-left - width / 2
                max-x = (x + width)
                diff = max-x - window.inner-width # react complains when using refs.ref.get-DOM-node!.viewport-width
                if diff > 0 then x - diff else x

            switch popup
            | \data-source-cue-popup =>
                DataSourceCuePopup do
                    left: left-from-width
                    data-source-cue: data-source-cue
                    on-change: (data-source-cue) ~> 
                        <~ @set-state {data-source-cue}
                        @save-to-client-storage-debounced!

            | \parameters-popup =>
                div do 
                    class-name: 'parameters-popup popup'
                    style: left: left-from-width 400
                    key: \parameters-popup
                    AceEditor do
                        editor-id: "parameters-editor"
                        value: @state.parameters
                        width: 400
                        height: 300
                        on-change: (value) ~> 
                            <~ @set-state parameters : value
                            @save-to-client-storage-debounced!

            | \share-popup =>
                [err, parameters-object] = compile-and-execute-livescript parameters, {}
                SharePopup do 
                    host: window.location.host
                    left: left-from-width
                    query-id: query-id
                    branch-id: branch-id
                    parameters: if !!err then {} else parameters-object
                    data-source-cue: data-source-cue

            | \tags-popup =>
                div do 
                    class-name: 'tags-popup popup'
                    style: 
                        left: left-from-width 400
                        width: 400
                        overflow: \visible
                    key: \tags-popup
                    ReactSelectize do 
                        add-options: true
                        values: tags
                        options: existing-tags
                        on-change: ~> 
                            <~ @set-state tags: it
                            @save-to-client-storage-debounced!
                        on-options-change: ~> @set-state existing-tags: it

            # DIALOGS
            if !!dialog
                div {class-name: \dialog-container},
                    match dialog
                    | \save-conflict =>
                        ConflictDialog do 
                            queries-in-between: queries-in-between
                            on-cancel: ~> @set-state {dialog: null, queries-in-between: null}
                            on-resolution-select: (resolution) ~>
                                uid = generate-uid!
                                match resolution
                                | \new-commit => @POST-document {} <<< @document-from-state! <<< {query-id: uid, parent-id: queries-in-between.0, branch-id, tree-id}
                                | \fork => @POST-document {} <<< @document-from-state! <<< {query-id: uid, parent-id: query-id, branch-id: uid, tree-id}
                                | \reset => @set-state (@state-from-document remote-document)
                                @set-state {dialog: null, queries-in-between: null}
                    | \settings =>
                        SettingsDialog do
                            initial-urls: @state.client-external-libs
                            initial-transpilation-language: @state.transpilation-language
                            on-change: ({urls, transpilation-language}) ~>
                                @set-state do
                                    client-external-libs: urls
                                    transpilation-language: transpilation-language
                                    dialog: null
                                @save-to-client-storage-debounced!
                            on-cancel: ~> @set-state dialog: null
                        
            div {class-name: \content},

                # EDITORS
                div do 
                    class-name: \editors
                    style: width: editor-width
                    [
                        {
                            editor-id: \query
                            editable-title: true
                            resizable: true
                        }
                        {
                            editor-id: \transformation
                            title: \Transformation
                            editable-title: false
                            resizable: true
                        }
                        {
                            editor-id: \presentation
                            title: \Presentation
                            editable-title: false
                            resizable: true
                        }
                    ] |> map ({editable-title, editor-id, resizable, title}:editor) ~>

                        div {class-name: \editor, key: editor-id},

                            # EDITABLE TITLE
                            div do 
                                class-name: \editor-title
                                on-mouse-down: (e) ~>
                                    initialY = e.pageY
                                    initial-heights = ["transformation", "presentation", "query"]
                                        |> map (p) ~> [p, @state[camelize "#{p}-editor-height"]]
                                        |> pairs-to-obj
                                    $ window .on \mousemove, ({pageY}) ~> 
                                        diff = pageY - initialY
                                        match editor-id 
                                            | "transformation" =>
                                                transformation-editor-height = initial-heights.transformation - diff
                                                query-editor-height = initial-heights.query + diff
                                                if transformation-editor-height > 0 and query-editor-height > 0
                                                    @set-state {transformation-editor-height, query-editor-height}
                                            | "presentation" =>
                                                transformation-editor-height = initial-heights.transformation + diff
                                                presentation-editor-height = initial-heights.presentation - diff
                                                if transformation-editor-height > 0 and presentation-editor-height > 0
                                                    @set-state {transformation-editor-height, presentation-editor-height}
                                    $ window .on \mouseup, -> $ window .off \mousemove .off \mouseup
                                if editable-title 
                                    input do
                                        type: \text
                                        value: title or @state["#{editor-id}Title"]
                                        on-change: ({current-target:{value}}) ~> 
                                            <~ @set-state {"#{editor-id}Title" : value}
                                            @save-to-client-storage-debounced!
                                else
                                    title

                            # ACE EDITOR
                            AceEditor {
                                editor-id: "#{editor-id}-editor"
                                value: @state[editor-id]
                                width: @state.editor-width
                                height: @state["#{editor-id}EditorHeight"]
                                on-change: (value) ~>
                                    <~ @set-state {"#{editor-id}" : value}
                                    @save-to-client-storage-debounced!
                            } <<< ui-protocol[data-source-cue.query-type]?[camelize "#{editor-id}-editor-settings"] @state.transpilation-language
                            

                # RESIZE HANDLE
                div do
                    class-name: \resize-handle
                    ref: \resize-handle
                    on-mouse-down: (e) ~>
                        initialX = e.pageX
                        initial-width = @state.editor-width
                        $ window .on \mousemove, ({pageX}) ~> 
                            <~ @set-state {editor-width: initial-width + (pageX - initialX)}
                            @update-presentation-size!
                        $ window .on \mouseup, -> $ window .off \mousemove .off \mouseup
                
                # PRESENTATION CONTAINER
                div do
                    ref: camelize \presentation-container
                    class-name: "presentation-container #{if !!executing-op then 'executing' else ''}"

                    # PRESENTATION: operations on this div are not controlled by react
                    div {ref: \presentation, class-name: \presentation}

                    # STATUS BAR
                    if !!displayed-on
                        time-formatter = d3.time.format("%d %b %I:%M %p")
                        items = 
                            * title: 'Displayed on'
                              value: time-formatter new Date displayed-on
                            * title: 'From cache'
                              value: if from-cache then \Yes else \No
                              show: !execution-error
                            * title: 'Cached on'
                              value: time-formatter new Date execution-end-time
                              show: !execution-error and from-cache
                            * title: 'Execution time'
                              value: "#{execution-duration / 1000} seconds"
                              show: !execution-error
                        div do 
                            class-name: \status-bar
                            items 
                                |> filter -> (typeof it.show == \undefined) or !!it.show
                                |> map ({title, value}) ->
                                    div null,
                                        label null, title
                                        span null, value
    
    # update-presentation-size :: a -> Void
    update-presentation-size: !->
        left = @state.editor-width + 5
        @refs.presentation-container.get-DOM-node!.style <<<
            left: left
            width: window.inner-width - left
            height: window.inner-height - @refs.menu.get-DOM-node!.offset-height
    
    # execute :: a -> Void
    execute: !->
        return if !!@state.executing-op

        {data-source-cue, query, transformation, presentation, parameters, cache, transpilation-language} = @state

        # display-error :: Error -> Void
        display-error = (err) !~>
            pre = $ "<pre/>"
            pre.html err.to-string!
            $ @refs.presentation.get-DOM-node! .empty! .append pre
            @set-state {execution-error: true}

        # process-query-result :: Result -> Void
        process-query-result = (result) !~>
            
            # clean existing presentation
            $ @refs.presentation.get-DOM-node! .empty!

            if !!parameters and parameters.trim!.length > 0
                [err, parameters-object] = compile-and-execute-livescript parameters, {}
                console.log err if !!err

            parameters-object ?= {}

            compile = switch transpilation-language
                | 'livescript' => compile-and-execute-livescript 
                | 'javascript' => compile-and-execute-javascript
            

            [err, func] = compile "(#transformation\n)", {} <<< transformation-context! <<< parameters-object <<< (require \prelude-ls)
            return display-error "ERROR IN THE TRANSFORMATION COMPILATION: #{err}" if !!err
            
            try
                transformed-result = func result
            catch ex
                return display-error "ERROR IN THE TRANSFORMATION EXECUTAION: #{ex.to-string!}"

            [err, func] = compile do 
                "(#presentation\n)"
                {d3, $} <<< transformation-context! <<< presentation-context! <<< parameters-object <<< (require \prelude-ls)
            return display-error "ERROR IN THE PRESENTATION COMPILATION: #{err}" if !!err
            
            try
                func @refs.presentation.get-DOM-node!, transformed-result
            catch ex
                return display-error "ERROR IN THE PRESENTATION EXECUTAION: #{ex.to-string!}"

            @set-state {execution-error: false}

        # use client cache if the query or its dependencies did not change
        sdocument = @document-from-state!
        if cache and !!@cached-execution and (all (~> sdocument[it] `is-equal-to-object` @cached-execution?.document?[it]), <[query parameters dataSourceCue transpilation]>)
            @set-state {executing-op: generate-uid!}
            {result, execution-end-time} = @cached-execution.result-with-metadata
            process-query-result result
            set-timeout do
                ~> @set-state {executing-op: "", displayed-on: Date.now!, from-cache: true, execution-duration: 0, execution-end-time}
                0

        # POST the document to the server for execution & cache the response
        else
            op-id = generate-uid!
            $.ajax {
                type: \post
                url: \/apis/execute
                content-type: 'application/json; charset=utf-8'
                data-type: \json
                data: JSON.stringify {op-id, document: @document-from-state!, cache}
                success: ({result, from-cache, execution-end-time, execution-duration}:result-with-metadata) ~>
                    @cached-execution = {document: @document-from-state!, result-with-metadata}
                    process-query-result result
                    keywords-from-query-result = switch 
                        | is-type 'Array', result =>  result ? [] |> take 10 |> get-all-keys-recursively (-> true) |> unique
                        | is-type 'Object', result => get-all-keys-recursively (-> true), result
                        | _ => []
                    <~ @set-state {from-cache, execution-end-time, execution-duration, keywords-from-query-result}
                    if document[\webkitHidden]
                        notification = new notifyjs do 
                            'Pipe: query execution complete'
                            body: "Completed execution of (#{@state.query-title}) in #{@state.execution-duration / 1000} seconds"
                            notify-click: -> window.focus!
                        notification.show!
                error: ({response-text}?) -> display-error response-text
                complete: ~> @set-state {displayed-on: Date.now!, executing-op: ""}
            }
            @set-state {executing-op: op-id}

    # POST-document :: Document -> (Document -> Void) -> Void
    POST-document: (document-to-save, callback) !->
        $.ajax {
            type: \post
            url: \/apis/save
            content-type: 'application/json; charset=utf-8'
            data-type: \json
            data: JSON.stringify document-to-save
        }
            ..done ({query-id, branch-id}:saved-document) ~>
                client-storage.delete-document @props.params.query-id
                @set-state {} <<< (@state-from-document saved-document) <<< {remote-document: saved-document}
                @transition-to "/branches/#{branch-id}/queries/#{query-id}"
                callback saved-document if !!callback
            ..fail ({response-text}?) ~>
                [err, queries-in-between]? = do ->
                    return [\empty-error] if !response-text
                    try
                        {queries-in-between}? = JSON.parse response-text
                    catch exception
                        return [\parse-error]
                    return [\unknown-error] if !queries-in-between
                    [\save-conflict, queries-in-between]
                match err
                | \save-conflict => @set-state {dialog: \save-conflict, queries-in-between}
                | _ => alert "Error: #{err}, #{response-text}"
    
    # returns a list of document properties (from current UIState) that diverged from the remote document
    # changes-made :: a -> [String]
    changes-made: ->

        # there are no changes made if the query does not exist on the server 
        return [] if !@state.remote-document

        unsaved-document = @document-from-state!
        <[query transformation presentation parameters queryTitle dataSourceCue tags]>
            |> filter ~> !(unsaved-document?[it] `is-equal-to-object` @state.remote-document?[it])

    # converts the current UIState to Document & POST's it as a "save" request to the server
    # save :: (Document -> Void) -> Void
    save: (callback) !->
        if @changes-made!.length == 0
            callback @document-from-state! if !!callback
            return

        uid = generate-uid! 
        {query-id, tree-id, parent-id}:document = @document-from-state!

        # a new query-id is generated at the time of save, parent-id is set to the old query-id
        # expect in the case of a forked-query (whose parent-id is saved in the local-storage at the time of fork)
        @POST-document do 
            {} <<< document <<<
                query-id: uid
                parent-id: switch @props.params.branch-id
                    | \local => null
                    | \local-fork => parent-id
                    | _ => query-id
                branch-id: if (@props.params.branch-id.index-of \local) == 0 then uid else @props.params.branch-id
                tree-id: tree-id or uid
            callback

    # save to client storage only if the document has loaded
    # save-to-client-storage :: a -> Void
    save-to-client-storage: !-> 
        if !!@state.remote-document
            client-storage.save-document @props.params.query-id, @document-from-state!

    # loads the document from local cache (if present) or server
    # load :: Props -> Void
    load: (props) !->
        {branch-id, query-id}? = props.params

        load-document = (query-id, url) ~> 
            local-document = client-storage.get-document query-id
            $.getJSON url
                ..done (document) ~>
                    
                    # load local-document if present otherwise load the remote document
                    document-to-load = if !!local-document then local-document else document
                    state-from-document = @state-from-document document-to-load
                    <~ @set-state {} <<< state-from-document <<< 

                        # existing-tags must also include tags saved on client storage 
                        existing-tags: ((@state.existing-tags ? []) ++ (state-from-document.tags |> map -> label: it, value: it))
                            |> unique-by (.value)
                            |> sort-by (.label)
                        
                        # state.remote-document is used to check if the client copy has diverged
                        remote-document: document

                    @update-presentation-size!

                ..fail ({response-text}?) ~> 
                    alert "unable to load query: #{response-text}"
                    window.location.href = \/

        # :) if branch id & query id are present
        return load-document query-id, "/apis/queries/#{query-id}" if !!query-id and !(branch-id in <[local localFork]>)            
        
        # redirect user to /branches/local/queries/:queryId if branchId is undefined
        return @replace-with "/branches/local/queries/#{generate-uid!}" if typeof branch-id == \undefined

        throw "this case must be handled by express router" if !(branch-id in <[local localFork]>)

        # try to fetch the document from local-storage on failure we make an api call to get the default-document
        load-document query-id, \/apis/defaultDocument

    # React component life cycle method (invoked once the component was renderer to the DOM)
    # component-did-mount :: a -> Void
    component-did-mount: !->

        # setup auto-completion
        transformation-keywords = ([transformation-context!, require \prelude-ls] |> concat-map keywords-from-object) ++ alphabet
        d3-keywords = keywords-from-object d3
        presentation-keywords = ([presentation-context!, require \prelude-ls] |> concat-map keywords-from-object) ++ alphabet
        @default-completers =
            * protocol: 
                get-completions: (editor, , , prefix, callback) ~>
                    keywords-from-query-result = @state[camelize \keywords-from-query-result]
                    range = editor.getSelectionRange!.clone!
                        ..set-start range.start.row, 0
                    text = editor.session.get-text-range range
                    [keywords, meta] = match editor.container.id
                        | \transformation-editor => [transformation-keywords ++ keywords-from-query-result, \transformation]
                        | \presentation-editor => [(if /.*d3\.($|[\w-]+)$/i.test text then d3-keywords else presentation-keywords), \presentation]
                        | _ => [alphabet, editor.container.id]
                    callback null, (convert-to-ace-keywords keywords, meta, prefix)
            ...
        ace-language-tools.set-completers (@default-completers |> map (.protocol))

        # auto completion for tags
        $.ajax do 
            url: \/apis/tags
            content-type: 'application/json; charset=utf-8'
            data-type: \json
            success: (existing-tags) ~> 
                @set-state do 
                    existing-tags: ((@state.existing-tags ? []) ++ (existing-tags |> map -> label: it, value: it))
                        |> unique-by (.value)
                        |> sort-by (.label)

        # data loss prevent on crash
        @save-to-client-storage-debounced = _.debounce @save-to-client-storage, 350
        window.onbeforeunload = ~> 
            if !@props.auto-reload and @changes-made!.length > 0
                @save-to-client-storage!
                return "You have NOT saved your query. Stop and save if your want to keep your query."

        # update the size of the presentation on resize (based on size of editors)
        $ window .on \resize, ~> @update-presentation-size!
        @update-presentation-size!

        # load the document based on the url
        @load @props
        notifyjs.request-permission! if notifyjs.needs-permission

        # selects presentation content only
        key 'command + a', (e) ~> 
            return true if e.target != document.body
            range = document.create-range!
                ..select-node-contents @refs.presentation.get-DOM-node!
            selection = window.get-selection!
                ..remove-all-ranges!
                ..add-range range
            cancel-event e

    # React component life cycle method (invoked before props are set)
    # component-will-receive-props :: Props -> Void
    component-will-receive-props: (props) !->
        # return if branch & query id did not change
        return if props.params.branch-id == @props.params.branch-id and props.params.query-id == @props.params.query-id

        # return if the document with the new changes to props is already loaded
        return if props.params.branch-id == @state.branch-id and props.params.query-id == @state.query-id

        @load props    

    # React component life cycle method (invoked after the render function)
    # updates the list of auto-completers if the data-source-cue has changed
    # component-did-update :: Props -> State -> Void
    component-did-update: (prev-props, prev-state) !->

        # data source auto complete
        do ~>
            {data-source-cue} = @state

            # return if the data-source-cue is not complete or there is no change in the data-source-cue
            return if !data-source-cue.complete or data-source-cue `is-equal-to-object` prev-state.data-source-cue

            # @completers is an array that stores a completer for each data-source-cue
            @completers = [] if !@completers

            # tries to find and return an exiting completer for the current data-source-cue iff the completer has a protocol property
            existing-completer = @completers |> find -> it.data-source-cue `is-equal-to-object` data-source-cue
            return ace-language-tools.set-completers [existing-completer.protocol] ++ (@default-completers |> map (.protocol)) if !!existing-completer?.protocol
            
            completer = existing-completer or {data-source-cue}

            # aborts any previous on-going requests for keywords before starting a new one
            # on success updates the protocol property of the completer
            @keywords-request.abort! if !!@keywords-request
            @keywords-request = $.ajax do
                type: \post
                url: "/apis/keywords"
                content-type: 'application/json; charset=utf-8'
                data-type: \json
                data: JSON.stringify data-source-cue
                success: (keywords) ~>
                    completer.protocol =
                        get-completions: (editor, , , prefix, callback) ->
                            range = editor.getSelectionRange!.clone!
                                ..set-start range.start.row, 0
                            text = editor.session.get-text-range range
                            if editor.container.id == \query-editor
                                callback null, (convert-to-ace-keywords keywords ++ alphabet, data-source-cue.type, prefix)    
                    if data-source-cue `is-equal-to-object` @state.data-source-cue
                        ace-language-tools.set-completers [completer.protocol] ++ (@default-completers |> map (.protocol)) 

            # a completer may already exist (but without a protocol, likely because the keywords request was aborted before)
            @completers.push completer if !existing-completer

        # client-external-libs
        do ~>
            addUrls = @state.client-external-libs `difference` prev-state.client-external-libs

            removeUrls = prev-state.client-external-libs `difference` @state.client-external-libs

            addUrls |> each (url) ->
                script = document.create-element "script"
                    ..src = url
                document.head.append-child script

            removeUrls |> each (url) ->
                $ "head > script[src='#{url}'" .remove!

    # React class method
    # get-initial-state :: a -> UIState
    get-initial-state: ->
        {
            query-id: null, parent-id: null, branch-id: null, tree-id: null,
            data-source-cue: {query-type: \mongodb, kind: \partial-data-source, complete: false}
            query: ""
            query-title: "Untitled query"
            transformation: ""
            presentation: ""
            parameters: ""
            existing-tags: []
            tags: []
            editor-width: 550
            dialog: false
            popup: null
            cache: true # user checked the cache checkbox
            from-cache: false # latest result is from-cache (it is returned by the server on execution)
            executing-op: 0
            keywords-from-query-result: []
            transpilation-language: 'livescript' # javascript or livescript
            client-external-libs: []
        } <<< editor-heights!

    # converting the document to a flat object makes it easy to work with 
    # state-from-document :: Document -> UIState
    state-from-document: ({
        query-id, parent-id, branch-id, tree-id, data-source-cue, query-title, query,
        transformation, presentation, parameters, ui, transpilation,
        client-external-libs, tags
    }?) ->
        {
            query-id, parent-id, branch-id, tree-id, data-source-cue, query-title, query
            transformation, presentation, parameters, 
            tags: tags ? []
            editor-width: ui?.editor?.width or @state.editor-width
            transpilation-language: transpilation?.query ? "livescript"
            client-external-libs: client-external-libs ? []
        } <<< editor-heights do 
            ui?.query-editor?.height or @state.query-editor-height
            ui?.transformation-editor?.height or @state.transformation-editor-height
            ui?.presentation-editor?.height or @state.presentation-editor-height

    # document-from-state :: a -> Document
    document-from-state: ->
        {
            query-id, parent-id, branch-id, tree-id, data-source-cue, query-title, query,
            transformation, presentation, parameters, editor-width, query-editor-height,
            transformation-editor-height, presentation-editor-height, transpilation-language, 
            client-external-libs, tags
        } = @state
        {
            query-id
            parent-id
            branch-id
            tree-id
            data-source-cue
            query-title
            transpilation:
                query: transpilation-language
                transformation: transpilation-language
                presentation: transpilation-language
            query
            transformation
            presentation
            tags
            client-external-libs
            parameters
            ui:
                editor:
                    width: editor-width
                query-editor:
                    height: query-editor-height
                transformation-editor:
                    height: transformation-editor-height
                presentation-editor:
                    height: presentation-editor-height
        }