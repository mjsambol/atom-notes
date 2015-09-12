path = require 'path'
fs = require 'fs-plus'
_ = require 'underscore-plus'
{$, $$, SelectListView} = require 'atom-space-pen-views'
DocQuery = require 'docquery'

module.exports =
class NotationalVelocityView extends SelectListView
  initialize: (state) ->
    @initializedAt = new Date()
    super
    @addClass('nvatom from-top overlay')
    @rootDirectory = atom.config.get('nvatom.directory')
    if !fs.existsSync(@rootDirectory)
      throw new Error("The given directory #{@rootDirectory} does not exist. "
        + "Set the note directory to the existing one from Settings.")
    @skipPopulateList = false
    @prevCursorPosition = 0
    @documentsLoaded = false
    @docQuery = new DocQuery(@rootDirectory, {recursive: true})
    @docQuery.on "ready", () =>
      @documentsLoaded = true
      @setLoading()
      @populateList()
    @docQuery.on "added", (fileDetails) =>
      @populateList() if @documentsLoaded
    @docQuery.on "updated", (fileDetails) =>
      @populateList() if @documentsLoaded
    @docQuery.on "removed", (fileDetails) =>
      @populateList() if @documentsLoaded
    if !atom.config.get('nvatom.enableLunrPipeline')
      @docQuery.searchIndex.pipeline.reset()

  isCursorProceeded: ->
    editor = @filterEditorView.model
    currCursorPosition = editor.getCursorBufferPosition().column
    isCursorProceeded = @prevCursorPosition < currCursorPosition
    @prevCursorPosition = currCursorPosition
    return isCursorProceeded

  selectItem: (filteredItems, filterQuery) ->
    isCursorProceeded = @isCursorProceeded()

    for item in filteredItems
      if item.title.match(///^#{filterQuery}$///i) != null
        # autoselect
        n = filteredItems.indexOf(item) + 1
        @selectItemView(@list.find("li:nth-child(#{n})"))
        return

    for item in filteredItems
      if item.title.match(///^#{filterQuery}///i) != null && isCursorProceeded
        # autocomplete
        @skipPopulateList = true
        editor = @filterEditorView.model
        editor.setText(filterQuery + item.title.slice(filterQuery.length))
        editor.selectLeft(item.title.length - filterQuery.length)

        # autoselect
        n = filteredItems.indexOf(item) + 1
        @selectItemView(@list.find("li:nth-child(#{n})"))

  filter: (filterQuery) ->
    if filterQuery == "" || filterQuery == undefined
      return @docQuery.documents
    return @docQuery.search(filterQuery)

  getFilterKey: ->
    'filetext'

  toggle: ->
    if @panel?.isVisible()
      @hide()
    else if @documentsLoaded
      @populateList()
      @show()
    else
      @setLoading("Loading documents")
      @show()

  viewForItem: (item) ->
    content = item.body[0...100]

    $$ ->
      @li class: 'two-lines', =>
        @div class: 'primary-line', =>
          @span "#{item.title}"
          @div class: 'metadata', "#{item.modifiedAt.toLocaleDateString()}"
        @div class: 'secondary-line', "#{content}"

  confirmSelection: ->
    item = @getSelectedItem()
    filePath = null
    sanitizedQuery = @getFilterQuery().replace(/\s+$/, '')
    calculatedPath = path.join(@rootDirectory, sanitizedQuery + '.md')
    if item?
      filePath = item.filePath
    else if fs.existsSync(calculatedPath)
      filePath = calculatedPath
    else if sanitizedQuery.length > 0
      filePath = calculatedPath
      fs.writeFileSync(filePath, '')

    if filePath
      atom.workspace.open(filePath).then (editor) ->
        save = ->
          atom.packages.deactivatePackage 'whitespace'
          editor.save()
          atom.packages.activatePackage 'whitespace'
        debouncedSave = _.debounce save, 1000
        editor.onDidStopChanging () ->
          debouncedSave() if editor.isModified()

    @cancel()

  destroy: ->
    @cancel()
    @panel?.destroy()

  show: ->
    @storeFocusedElement()
    @panel ?= atom.workspace.addModalPanel(item: this)
    @panel.show()
    @focusFilterEditor()

  cancelled: ->
    @hide()

  hide: ->
    @panel?.hide()

  getFilterQuery: ->
    editor = @filterEditorView.model
    fullText = editor.getText()
    selectedText = editor.getSelectedText()
    return fullText.substring(0, fullText.length - selectedText.length)

  populateList: ->
    filterQuery = @getFilterQuery()
    filteredItems = @filter(filterQuery)

    @list.empty()
    if filteredItems.length
      @setError(null)

      for i in [0...Math.min(filteredItems.length, @maxItems)]
        item = filteredItems[i]
        itemView = $(@viewForItem(item))
        itemView.data('select-list-item', item)
        @list.append(itemView)

      @selectItem(filteredItems, filterQuery)

    else
      @setError(@getEmptyMessage(@docQuery.documents.length, filteredItems.length))

  schedulePopulateList: ->
    if !@skipPopulateList
      super
    @skipPopulateList = false
