#!/bin/bash

set -e

builddir="build"

if [ ! -d "$builddir" ]; then
  meson setup "$builddir"
fi

meson compile -C "$builddir"

# copy the binary next to ./data so the editor finds its runtime files
cp "$builddir/lite" lite

echo "done"
