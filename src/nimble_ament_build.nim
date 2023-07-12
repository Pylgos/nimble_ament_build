import std/[os, sets, json, tables, osproc, sequtils, strformat, tempfiles, strutils, terminal]


type
  NimbleConf = object
    name: string
    srcDir: string
    skipDirs, skipFiles, skipExt, installDirs, installFiles, installExt, bin: seq[string]
    namedBin: Table[string, string]

  BuildError = object of CatchableError


proc parseNimble(): NimbleConf =
  let res = execCmdEx("nimble dump --json", options={poUsePath})
  if res.exitCode != 0:
    raise newException(BuildError):
      "'nimble dump --json' failed:\n" & res.output
  let j = res.output.parseJson()

  for name, field in result.fieldPairs:
    field =
      if name in j:
        j[name].to(typeof(field))
      else:
        typeof(field).default


proc getNimbleTasks(): HashSet[string] =
  let res = execCmdEx("nimble tasks", options={poUsePath})
  if res.exitCode != 0:
    raise newException(BuildError):
      "'nimble dump --json' failed:\n" & res.output
  for line in res.output.splitLines:
    let tmp = line.split(' ', 1)
    if tmp.len == 2:
      result.incl tmp[0]


proc execNimbleTask(taskName: string, flags: openArray[string]) =
  echo fmt"Executing task '{taskName}'"
  let f = flags.mapIt(it.quoteShell).join(" ")
  let cmd = fmt"nimble {f} {taskName.quoteShell}"
  echo "Executing ", cmd
  let res = execCmdEx(cmd, options={poUsePath})
  if res.exitCode != 0:
    raise newException(BuildError):
      &"'{cmd}' failed:\n" & res.output
  echo res.output


proc execNimbleTaskIfExists(tasks: HashSet[string], taskName: string, flags: openArray[string]) =
  if taskName in tasks:
    execNimbleTask(taskName, flags)


proc build(
      installBase: string,
      buildBase: string = "",
      passNim: seq[string] = @[]): int =
  
  let buildBase =
    if buildBase == "":
      let tmp = createTempDir("nimble-ament-build-", "")
      echo fmt"Build base is not specified. Defaulting to '{tmp}'"
      tmp
    else:
      buildBase
  
  styledEcho "Reading nimble file"
  let nimbleConf = parseNimble()

  let
    buildDir = buildBase/"nimble_ament_build"
    nimcacheDir = buildDir/"nimcache"

  styledEcho "Package name: ", styleBright, nimbleConf.name
  styledEcho "Source dir  : ", styleBright, getCurrentDir()
  styledEcho "Install base: ", styleBright, installBase
  styledEcho "Build base  : ", styleBright, buildBase
  styledEcho "nimcache dir: ", styleBright, nimcacheDir

  var namedBins: seq[tuple[src, dest: string]]
  for b in nimbleConf.bin:
    let src =
      if nimbleConf.srcDir == "":
        b
      else:
        nimbleConf.srcDir/b
    namedBins.add (src, installBase/"lib"/nimbleConf.name/b)

  for (srcName, destName) in nimbleConf.namedBin.pairs:
    let
      src =
        if nimbleConf.srcDir == "": srcName
        else: nimbleConf.srcDir/srcName
      dest =
        if '/' in destName: installBase/destName
        else: installBase/"bin"/destName
    namedBins.add (src, dest)
  
  let tasks = getNimbleTasks()
  let taskFlags = [
    "--colors:on",
    fmt"-d:installBase={installBase}",
    fmt"-d:buildBase={buildBase}",
    fmt"--nimcache:{nimcacheDir}",
  ]
  let compileFlags = @[
    "-y",
    "--colors:on",
    fmt"--nimcache:{nimcacheDir}",
  ] & passNim

  tasks.execNimbleTaskIfExists("preBuild", taskFlags)
  
  for (src, dest) in namedBins:
    styledEcho styleBright, fgGreen, "Compiling ", fgWhite, src

    if dest.fileExists:
      removeFile(dest)
    elif dest.dirExists:
      removeDir(dest)

    let
      flags = compileFlags.map(quoteShell).join(" ")
      cmd = fmt"nimble c --out:{dest.quoteShell} {flags} {src.quoteShell}"
    styledEcho styleDim, "--> Executing: ", cmd
    let exitCode = execCmd(cmd)
    if exitCode != 0:
      raise newException(BuildError):
        fmt"Failed to build {src}"

  tasks.execNimbleTaskIfExists("postBuild", taskFlags)
  tasks.execNimbleTaskIfExists("preInstall", taskFlags)

  for d in nimbleConf.installDirs:
    echo "Installing directory ", d
    d.parentDir.createDir()
    copyDirWithPermissions(d, installBase/d)

  for f in nimbleConf.installFiles:
    echo "Installing file ", f
    f.parentDir.createDir()
    copyFileWithPermissions(f, installBase/f)
  
  createDir(installBase/"share/ament_index/resource_index/packages")
  writeFile(installBase/"share/ament_index/resource_index/packages"/nimbleConf.name, "")
  copyFile("package.xml", installBase/"share"/nimbleConf.name/"package.xml")
  
  tasks.execNimbleTaskIfExists("postInstall", taskFlags)

  return 0

proc test(buildBase, installBase: string, symlinkInstall = false, passNim: seq[string] = @[]): int =
  return 0

when isMainModule:
  import cligen
  dispatchMulti([build], [test])
