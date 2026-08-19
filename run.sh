#!/bin/bash

odin_args="--collection:libs=libs -debug -define:GLFW_SHARED=false -keep-executable"
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


