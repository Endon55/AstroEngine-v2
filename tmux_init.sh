#/bin/bash

session="Astro"

tmux new-session -d -s $session

tmux rename-window -t 0 'Main'

tmux send-keys -t 'Main' 'nvim .' C-m 

tmux new-window -t $session:1 -n 'build'

tmux new-window -t $session:2 -n 'build-shaders'
tmux send-keys -t 'build-shaders' "cd shaders/source" C-m

tmux attach-session -t $session:0
