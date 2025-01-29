function get_fps(file)
    txt = read(`$(ffprobe()) -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate $file`, String)
    m = match(r"(\d+)/(\d+)", txt)
    fps = if isnothing(m)
        @warn "no fps, invented a default of 30"
        30.0
    else
        num, denum = parse.(Int, m.captures)
        num/denum
    end
    return fps
end

function get_duration(file)
    txt = read(`$(ffprobe()) -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file`, String)
    dur = parse(Float64, txt)
    return dur
end
