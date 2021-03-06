fs = require("fs")
path = require("path")
match = require("match-files")
coffee = require("coffee-script")
jade = require("jade")
sty = require('sty')
app = null

directory = process.cwd()

console.info = (msg) ->
  console.log sty.red msg

console.debug = (msg) ->
  console.log sty.green msg



class Application
  constructor: ->
    app = this
    @program = require('commander')
    @titanium = null

    @program
      .version('0.0.4')
      .usage('[COMMAND] [OPTIONS]')
      #.option('-s, --setup', 'Setup lazy-alloy directory structure.')
      # .option('-c, --compile', 'Just compile.')
      # .option('-w, --watch', 'Watch file changes & compile.')
      .option('-p, --platform [platform]', '(watch) When done, run titanium on `platform`')
      .option('-d, --directory [dirname]', 'Set source directory (default `src/`)')

    @program.command('compile')
      .description('Just compile.')
      .action(@compile)

    @program.command('watch')
      .description('Watch file changes & compile.')
      .action(@watch)

    @program.command('build <platform>')
      .description('Run titanium on `platform`')
      .action(@build)

    @program.command('new')
      .description('Setup the lazy-alloy directory structure.')
      .action(@setup)

    @program.command('generate [type] [name]')
      .description('Generate a new (lazy-)alloy type such as a controller.')
      .action(@generate)

    @program.parse(process.argv)

  # start: ->
  #   return @compile() if @program.compile
  #   return @watch() if @program.watch
  #   return @build() if @program.platform

  #   console.info "nothing to do!"

  start: ->
    @subfolder = if @program.directory
      @program.directory += '/' unless @program.directory.charAt(subfolder.length-1) == '/'
    else
     'src/'
    @compiler = new Compiler(@subfolder)

  compile: ->
    app.start()
    app.compiler.all()

  build: (platform = app.program.platform) ->
    app.start()
    spawn = require("child_process").spawn
    exec = require("child_process").exec

    if app.titanium isnt null
      console.info "stopping titanium..."
      app.titanium.kill()

    alloy = exec "alloy compile", (error, stdout, stderr) ->
      console.debug stdout if stdout
      console.log stderr if stderr

    alloy.on 'exit', (code) =>
      console.log "alloy stopped with code #{ code }"

      if code isnt 1
        console.info "starting titanium..."

        @titanium = spawn "titanium", ["build", "-p", platform]

        @titanium.stdout.on "data", (data) ->
          console.log "titanium: " + data

        @titanium.stderr.on "data", (data) ->
          console.log "titanium: " + data

        @titanium.on "exit", (code) ->
          console.log "titanium exited with code " + code

  watch: ->
    app.start()
    watchr = require("watchr")

    console.info "Waiting for file change..."

    watchr.watch
      ignoreHiddenFiles: true
      paths: [directory]
      listeners:
        error: (err) ->
          console.log "an error occured:", err

        change: (changeType, filePath, fileCurrentStat, filePreviousStat) =>
          return unless changeType in ["create", "update"]

          #only compile correct files
          file = getFileType filePath
          return unless file

          app.compiler.files [filePath], file.fromTo[0], file.fromTo[1]

          app.build() if app.program.platform

    next: (err, watchers) ->
      if err
        return console.log("watching everything failed with error", err)
      else
        console.debug "Waiting for file change..."

  setup: ->
    app.start()
    new Generator().setup app.subfolder

  generate: (type, name) ->
    app.start()
    app.type = type
    app.name = name
    app.ensureType()

  ensureType: ->
    if app.type
      app.ensureName()
    else
      console.debug 'What should I generate?'
      app.program.choose ['controller', 'view', 'model', 'widget'], app.ensureName

  ensureName: (i, type) ->
    app.type = type if type
    if app.name # might not be needed for all future generators
      app.startGenerator()
    else
      app.program.prompt "Please enter a name for your #{app.type}: ", app.startGenerator

  startGenerator: (name) ->
    app.name = name if name
    new Generator().generate app.type, app.name

  getFileType = (path) ->
    #check if file path contains string
    inpath = (name) ->
      !!~ path.indexOf name

    return {type: "view", fromTo: ["jade", "xml"]} if inpath ".jade"
    return {type: "widgets/view", fromTo: ["jade", "xml"]} if inpath "widgets/view"

    return null unless inpath ".coffee"

    return {type: "style", fromTo: ["coffee", "tss"]} if inpath "styles/"
    return {type: "alloy", fromTo: ["coffee", "js"]} if inpath "alloy.coffee"
    return {type: "controller", fromTo: ["coffee", "js"]} if inpath "controllers/"
    return {type: "widgets/style", fromTo: ["coffee", "tss"]} if inpath "widgets/style"
    return {type: "widgets/controller", fromTo: ["coffee", "js"]} if inpath "widgets/controller"

class Compiler
  logger: console
  constructor: (@subfolder = 'src/') ->

  views: ->
    @process "views/", "jade", "xml"

  controllers: ->
    @process "controllers/", "coffee", "js"

  styles: ->
    @process "styles/", "coffee", "tss"

  widgets: ->
    widgets = fs.readdirSync "#{@subfolder}/widgets"
    for widget in widgets
      @process "widgets/#{widget}/views/", "jade", "xml"
      @process "widgets/#{widget}/styles/", "coffee", "tss"
      @process "widgets/#{widget}/controllers/", "coffee", "js"

  all: ->
    @views()
    @controllers()
    @styles()
    @widgets()

  process: (path, from, to) ->
    path = @subfolder + path
    @logger.info "Preprocessing #{ from } files in #{ path }"

    filter = (dir) ->
      # It should contain the expected extension but not a hidden file (starting with a dot)
      dir.indexOf(".#{ from }") isnt -1 and dir.indexOf(".") isnt 0

    match.find (process.cwd() + "/" + path), {fileFilters: [filter]}, (err, files) => @files files, from, to

  file: (from, output, type) ->
    @logger.debug "Building #{type}: #{from} --> #{output}"
    data = fs.readFileSync from, 'utf8'
    compiled = @build[type] data
    # Create the base path
    @mkdirPSync output.split('/')[0...-1]
    fs.writeFileSync output, compiled, 'utf8'

  files: (files, from, to, to_path) ->
    return @logger.debug "No '*.#{from}' files need to preprocess.. #{files.length} files" if files.length is 0

    # Create necessary directory in case it doesn't exist
    paths = ['app', 'app/controllers', 'app/styles', 'app/views']
    for path in paths
      unless fs.existsSync path
        fs.mkdirSync path

    for file in files
      break if !!~ file.indexOf "lazyalloy"

      output = file.substring(0, file.length - from.length).toString() + to
      output = output.replace(new RegExp('(.*)'+@subfolder), '$1app/') # Replacing subfolder with app. Only last occurence in case it exists twice in the path.

      @file file, output, to

  build:
    xml: (data) ->
      jade.compile(data,
        pretty: true
      )(this)

    tss: (data) ->
      data = @js data

      (data.replace "};", "").replace """
        var tss;

        tss = {

        """, ""

    js: (data) ->
      coffee.compile data.toString(), {bare: true}

    json: (data) ->
      data

  # The equivalent of running `mkdir -p <path>` on the command line
  mkdirPSync: (segments, pos=0) ->
    return if pos >= segments.length
    # Construct path at current segment
    segment = segments[pos]
    path = segments[0..pos].join '/'

    # Create path if it doesn't exist
    if path.length > 0
      unless fs.existsSync path
        fs.mkdirSync path
    # Go deeper
    @mkdirPSync segments, pos + 1

class Generator
  setup: (subfolder) ->
    console.info "Setting up folder structure at #{subfolder}"
    mkdir subfolder
    mkdir subfolder+'views'
    mkdir subfolder+'styles'
    mkdir subfolder+'controllers'
    mkdir subfolder+'widgets'
    console.debug 'Setup complete.'
    process.exit()

  generate: (type, name) ->
    switch type
      when 'controller'
        createController name
      when 'model'
        createModel name
      when 'jmk'
        not_yet_implemented()
      when 'model'
        createModel name
      when 'migration'
        not_yet_implemented()
      when 'view'
        createView name
      when 'widget'
        createWidget name
      else
        console.info "Don't know how to build #{type}"
    process.exit()

  createController = (name) ->
    console.debug "Creating controller #{name}"
    touch app.subfolder + 'controllers/' + name + '.coffee'
    createView name

  createView = (name) ->
    console.debug "Building view #{name}"
    touch app.subfolder + 'views/' + name + '.jade'
    createStyle name

  createStyle = (name) ->
    console.debug "Building style #{name}"
    touch app.subfolder + 'styles/' + name + '.coffee'

  createModel = (name) ->
    console.debug "Building model #{name}"
    touch app.subfolder + 'models/' + name + '.coffee'

  createWidget = (name) ->
    console.debug "Creating widget #{name}"
    mkdir app.subfolder + 'widgets/'
    mkdir app.subfolder + 'widgets/' + name
    mkdir app.subfolder + 'widgets/' + name + '/controllers/'
    mkdir app.subfolder + 'widgets/' + name + '/views/'
    mkdir app.subfolder + 'widgets/' + name + '/styles/'
    touch app.subfolder + 'widgets/' + name + '/controllers/widget.coffee'
    touch app.subfolder + 'widgets/' + name + '/views/widget.jade'
    touch app.subfolder + 'widgets/' + name + '/styles/widget.coffee'

  not_yet_implemented = ->
    console.info "This generator hasn't been built into lazy-alloy yet. Please help us out by building it in:"
    console.info "https://github.com/vastness/lazy-alloy"

  mkdir = (path) ->
    execUnlessExists fs.mkdirSync, path
  touch = (path) ->
    execUnlessExists fs.openSync, path, 'w'
  execUnlessExists = (func, path, attr = null) ->
    if fs.existsSync(path)
      console.debug("#{path} already exists, doing nothing")
    else
      func path, attr

module.exports = new Application
