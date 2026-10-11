#/bin/bash

session="Astro"

tmux new-session -d -s $session

tmux rename-window -t 0 'Main'

tmux send-keys -t 'Main' 'nvim .' C-m 

tmux split-window -h -d -t $session:Main
tmux resize-pane -R -t $session:Main.1 60 

tmux split-window -v -d -t $session:Main.0 
tmux resize-pane -D -t $session:Main.1 10 

tmux send-keys -t $session:Main.2 "opencode" C-m


tmux new-window -t $session -n 'nvim-config'
tmux send-keys -t $session:nvim-config "cd ../../.config/nvim" C-m

tmux new-window -t $session -n 'tmux-config'
tmux send-keys -t $session:tmux-config "cd ../../.config/tmux" C-m

tmux new-window -t $session -n 'rad-dbg'
tmux send-keys -t $session:rad-dbg "raddbg" C-m


tmux attach-session -t $session:0
