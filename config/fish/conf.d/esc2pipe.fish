# Esc inserts " |" at the cursor (quick pipe). Esc keeps closing the pager.
status is-interactive; or return 0

function _insert_pipe_on_esc
    if commandline --paging-mode
        commandline -f cancel
        return
    end
    commandline -i ' |'
end

bind \e _insert_pipe_on_esc
