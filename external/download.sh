#!/bin/sh

[ -e terminfo-1.8-0.src.rock ] || wget -nv https://luarocks.org/manifests/peterbillam/terminfo-1.8-0.src.rock
unzip -p terminfo-1.8-0.src.rock terminfo-1.8.tar.gz | tar -xz
