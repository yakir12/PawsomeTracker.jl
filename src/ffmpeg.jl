function get_sar(file)
    txt = read(`$(ffprobe()) -v error -select_streams v:0 -show_entries stream=sample_aspect_ratio -of default=noprint_wrappers=1:nokey=1 $file`, String)
    m = match(r"(\d+):(\d+)", txt)
    sar = /(parse.(Int, m.captures)...)
    return sar
end

function get_fps(file)
    txt = read(`$(ffprobe()) -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate $file`, String)
    m = match(r"(\d+)/(\d+)", txt)
    fps = /(parse.(Int, m.captures)...)
    return fps
end

function get_duration(file)
    txt = read(`$(ffprobe()) -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file`, String)
    dur = parse(Float64, txt)
    return dur
end

# function snap(file, ss)
#     cmd = `$(ffmpeg()) -loglevel 8 -ss $ss -i $file -frames:v 1 -q:v 2 -f image2pipe -`
#     io = open(cmd)
#     img = JpegTurbo.jpeg_decode(io)
#     return img
# end

function video2frames(path, file, start, stop, fps)
    t = stop - start
    _files = joinpath(path, "%03d.bmp")
    cmd = `$(ffmpeg()) -loglevel 8 -ss $start -i $file -t $t -r $fps -frame_pts true $_files`
    run(cmd)
    files = readdir(path, join=true)
    return files
end
