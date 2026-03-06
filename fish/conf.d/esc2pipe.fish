# ~/.config/fish/functions/pipe_plugin.fish

function insert_pipe_on_esc
    commandline -i " |"
    set -U CURSOR (math $CURSOR + 2)
end

bind \e 'insert_pipe_on_esc'

