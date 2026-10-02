function music --description "Shuffle-play ~/Music with mpv (start|stop|toggle)"
    switch "$argv[1]"
        case start
            mpv --no-video --shuffle ~/Music/*
        case stop
            pkill mpv
        case toggle
            if pgrep -x mpv >/dev/null
                pkill mpv
            else
                mpv --no-video --shuffle ~/Music/*
            end
        case '*'
            echo "usage: music start|stop|toggle" >&2
            return 1
    end
end
