ThreadHiding =
  init: ->
    return if g.VIEW isnt 'index' or !Conf['Thread Hiding'] and !Conf['Thread Hiding Link']

    @db = new DataBoard 'hiddenThreads'
    @syncCatalog()
    $.on d, 'IndexBuild', @onIndexBuild
    Thread.callbacks.push
      name: 'Thread Hiding'
      cb:   @node

  node: ->
    if data = ThreadHiding.db.get {boardID: @board.ID, threadID: @ID}
      ThreadHiding.hide @, data.makeStub
    return unless Conf['Thread Hiding']
    $.prepend @OP.nodes.root, ThreadHiding.makeButton @, 'hide'

  onIndexBuild: ({detail: nodes}) ->
    for root, i in nodes by 2
      thread = Get.threadFromRoot root
      continue unless thread.isHidden
      unless thread.stub
        nodes[i + 1].hidden = true
      else unless root.contains thread.stub
        # When we come back to a page, the stub is already there.
        ThreadHiding.makeStub thread, root
    return

  syncCatalog: ->
    # Sync hidden threads from the catalog into the index.
    hiddenThreads = ThreadHiding.db.get
      boardID: g.BOARD.ID
      defaultValue: {}
    hiddenThreadsOnCatalog = JSON.parse(localStorage.getItem "4chan-hide-t-#{g.BOARD}") or {}

    # Add threads that were hidden in the catalog.
    for threadID of hiddenThreadsOnCatalog
      unless threadID of hiddenThreads
        hiddenThreads[threadID] = {}

    # Remove threads that were un-hidden in the catalog.
    for threadID of hiddenThreads
      unless threadID of hiddenThreadsOnCatalog
        delete hiddenThreads[threadID]

    if (ThreadHiding.db.data.lastChecked or 0) > Date.now() - $.MINUTE
      # Was cleaned just now.
      ThreadHiding.cleanCatalog hiddenThreadsOnCatalog

    unless Object.keys(hiddenThreads).length
      ThreadHiding.db.delete boardID: g.BOARD.ID
      return
    ThreadHiding.db.set
      boardID: g.BOARD.ID
      val: hiddenThreads

  cleanCatalog: (hiddenThreadsOnCatalog) ->
    # We need to clean hidden threads on the catalog ourselves,
    # otherwise if we don't visit the catalog regularly
    # it will pollute the localStorage and our data.
    $.cache "//a.4cdn.org/#{g.BOARD}/threads.json", ->
      return unless @status is 200
      threads = {}
      for page in JSON.parse @response
        for thread in page.threads
          if thread.no of hiddenThreadsOnCatalog
            threads[thread.no] = hiddenThreadsOnCatalog[thread.no]
      if Object.keys(threads).length
        localStorage.setItem "4chan-hide-t-#{g.BOARD}", JSON.stringify threads
      else
        localStorage.removeItem "4chan-hide-t-#{g.BOARD}"

  menu:
    init: ->
      return if g.VIEW isnt 'index' or !Conf['Menu'] or !Conf['Thread Hiding Link']

      div = $.el 'div',
        className: 'hide-thread-link'
        textContent: 'Hide thread'

      apply = $.el 'a',
        textContent: 'Apply'
        href: 'javascript:;'
      $.on apply, 'click', ThreadHiding.menu.hide

      makeStub = $.el 'label',
        innerHTML: "<input type=checkbox checked=#{Conf['Stubs']}> Make stub"

      $.event 'AddMenuEntry',
        type: 'post'
        el: div
        order: 20
        open: ({thread, isReply}) ->
          if isReply or thread.isHidden
            return false
          ThreadHiding.menu.thread = thread
          true
        subEntries: [el: apply; el: makeStub]
    hide: ->
      makeStub = $('input', @parentNode).checked
      {thread} = ThreadHiding.menu
      ThreadHiding.hide thread, makeStub
      ThreadHiding.saveHiddenState thread, makeStub
      $.event 'CloseMenu'

  makeButton: (thread, type) ->
    a = $.el 'a',
      className: "#{type}-thread-button"
      innerHTML: "<span>[&nbsp;#{if type is 'hide' then '-' else '+'}&nbsp;]</span>"
      href:      'javascript:;'
    a.dataset.fullID = thread.fullID
    $.on a, 'click', ThreadHiding.toggle
    a
  makeStub: (thread, root) ->
    numReplies  = $$('.thread > .replyContainer', root).length
    numReplies += +summary.textContent.match /\d+/ if summary = $ '.summary', root
    opInfo = if Conf['Anonymize']
      'Anonymous'
    else
      $('.nameBlock', thread.OP.nodes.info).textContent

    a = ThreadHiding.makeButton thread, 'show'
    $.add a, $.tn " #{opInfo} (#{if numReplies is 1 then '1 reply' else "#{numReplies} replies"})"
    thread.stub = $.el 'div',
      className: 'stub'
    if Conf['Menu']
      $.add thread.stub, [a, Menu.makeButton()]
    else
      $.add thread.stub, a
    $.prepend root, thread.stub

  saveHiddenState: (thread, makeStub) ->
    hiddenThreadsOnCatalog = JSON.parse(localStorage.getItem "4chan-hide-t-#{g.BOARD}") or {}
    if thread.isHidden
      ThreadHiding.db.set
        boardID:  thread.board.ID
        threadID: thread.ID
        val: {makeStub}
      hiddenThreadsOnCatalog[thread] = true
    else
      ThreadHiding.db.delete
        boardID:  thread.board.ID
        threadID: thread.ID
      delete hiddenThreadsOnCatalog[thread]
    localStorage.setItem "4chan-hide-t-#{g.BOARD}", JSON.stringify hiddenThreadsOnCatalog

  toggle: (thread) ->
    unless thread instanceof Thread
      thread = g.threads[@dataset.fullID]
    if thread.isHidden
      ThreadHiding.show thread
    else
      ThreadHiding.hide thread
    ThreadHiding.saveHiddenState thread

  hide: (thread, makeStub=Conf['Stubs']) ->
    return if thread.isHidden
    threadRoot = thread.OP.nodes.root.parentNode
    thread.isHidden = true

    unless makeStub
      threadRoot.hidden = threadRoot.nextElementSibling.hidden = true # <hr>
      return

    ThreadHiding.makeStub thread, threadRoot

  show: (thread) ->
    if thread.stub
      $.rm thread.stub
      delete thread.stub
    threadRoot = thread.OP.nodes.root.parentNode
    threadRoot.nextElementSibling.hidden =
      threadRoot.hidden = thread.isHidden = false
