#!/bin/bash

clear

VULKAN=(/usr/local/src/vulkan/*)
VULKAN_SDK="${VULKAN[0]}/$(uname -m)"
echo $VULKAN_SDK
Name="Astro"

odin_args="--collection:libs=libs -debug -define:GLFW_SHARED=false -keep-executable -out:$Name.bin -extra-linker-flags:\"-L$VULKAN_SDK/lib -Wl,-rpath,$VULKAN_SDK/lib\""
odin_command="run"
prefix=""

for arg in "$@"; do
    
    if [[ arg -eq "gdb" ]]; then
        prefix="gdb "
    fi

done


instruction="$prefix odin $odin_command src $odin_args"
echo "$instruction"
eval "$instruction"

#
# if [[ "$#" -eq 0 ]]; then
#     odin run src $odin_args
#     exit 1
# fi


