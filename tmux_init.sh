#/bin/bash

session="Astro"
#tput cols/lines is a terminal command that reads the terminal size and we send that to tmux
tmux new-session -d -s $session -x "$(tput cols)" -y "$(tput lines)"
tmux rename-window -t $session:0 'Main'
tmux send-keys -t $session:Main 'nvim .' C-m

# right pane: 10% wide
tmux split-window -h -d -l 10% -t $session:Main.0

# bottom pane under the main pane (becomes index 1; right pane becomes index 2)
tmux split-window -v -d -l 20% -t $session:Main.0

tmux send-keys -t $session:Main.2 "opencode" C-m

tmux new-window -t $session -n 'nvim-config'
tmux send-keys -t $session:nvim-config "cd ../../.config/nvim" C-m

tmux new-window -t $session -n 'tmux-config'
tmux send-keys -t $session:tmux-config "cd ../../.config/tmux" C-m

tmux new-window -t $session -n 'rad-dbg'
#tmux send-keys -t $session:rad-dbg "raddbg" C-m


tmux attach-session -t $session:0
