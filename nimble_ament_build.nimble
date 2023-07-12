# Package

version       = "0.1.0"
author        = "Pylgos"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
namedBin      = {"nimble_ament_build": "nimble-ament-build"}.toTable


# Dependencies

requires "nim >= 1.9.5"
requires "cligen"

task reinstall, "reinstall":
  exec "nimble uninstall -y nimble_ament_build"
  exec "nimble install"
