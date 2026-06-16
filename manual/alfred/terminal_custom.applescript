on alfred_script(q)
    do shell script "/opt/homebrew/bin/tmux new-window -t dev -c $HOME \\; send-keys " & quoted form of q & " Enter"
    tell application "Ghostty" to activate
end alfred_script
