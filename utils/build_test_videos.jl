using FFMPEG_jll

function start_location2rowcol(start_location, width, height)
    if start_location == :middle
        (height ÷ 2, width ÷ 2)
    elseif start_location == :off
        (round(Int, 0.75*height), round(Int, 0.35*width))
    else
        error("unknown start location for the generation of test videos for PawsomeTracker.jl")
    end
end

const seconds = 1

path = "/home/yakir/Sync/PawsomeTracker.jl/utils/vids"
if isdir(path)
    rm(path; force = true, recursive = true)
end
mkdir(path)

function mkvideos(fps, start_location, width, height, target_width, darker_target, aspect, nsegments, path)
    row, col = start_location2rowcol(start_location, width, height)
    # bkgd_c = darker_target ? "white" : "black"
    target_c = darker_target ? 0 : 255
    w2 = width ÷ aspect
    fldr = join((fps, start_location, row, col, width, height, target_width, darker_target, aspect, nsegments), "_")
    mkdir(joinpath(path, fldr))
    if nsegments == 1
        run(`$(FFMPEG_jll.ffmpeg()) -y -loglevel error -f lavfi -i color=white:s=$(width)x$height:d=$seconds:r=$fps -vf "geq=lum='if(lt(sqrt((X-$col+($width/2.5)*sin(0.5*PI*N/$fps))^2+(Y-$row)^2),$(target_width/2)),$target_c,$(target_c == 255 ? 0 : 255))':cb=128:cr=128,scale=$w2:$height,setdar=$aspect,setsar=$aspect" -pix_fmt yuv420p $(joinpath(path, fldr, "output.mp4"))`);
    else
        segment_time = seconds/nsegments
        run(`$(FFMPEG_jll.ffmpeg()) -y -loglevel error -f lavfi -i color=white:s=$(width)x$height:d=$seconds:r=$fps -vf "geq=lum='if(lt(sqrt((X-$col+($width/2.5)*sin(0.5*PI*N/$fps))^2+(Y-$row)^2),$(target_width/2)),$target_c,$(target_c == 255 ? 0 : 255))':cb=128:cr=128,scale=$w2:$height,setdar=$aspect,setsar=$aspect" -pix_fmt yuv420p -force_key_frames "expr:gte(t,n_forced*$segment_time)" -f segment -segment_time $segment_time $(joinpath(path, fldr, "output_%02d.mp4"))`);
    end
end

@sync for fps in (25, 50), start_location in (:middle, :off), width in (100, 300), height in (100, 300), target_width in (5, 30), darker_target in (true, false), aspect in (0.5, 1, 2), nsegments in (1, 3)
    Threads.@spawn mkvideos(fps, start_location, width, height, target_width, darker_target, aspect, nsegments, path)
end

#
#
# using ColorTypes, Printf, FFMPEG_jll, FixedPointNumbers, ImageDraw, FileIO, ImageTransformations, CSV
#
# const pps = 37 # pixels per second, how many pixels the target moves per second
#
#
# function track2right(start_location, width, height, fps, pps)
#     row, col = start_location2rowcol(start_location, width, height)
#     step = pps/fps
#     [(row, round(Int, j)) for j in range(col, 0.9width; step)]
# end
#
# function drawone(blank, ij, target_radius, target_c, aspect, temp_path, i, bkgd_c)
#     frame = draw(blank, CirclePointRadius(Point(CartesianIndex(ij)), target_radius), target_c) 
#     if aspect ≠ 1
#         frame = imresize(frame, ratio = (1, 1/aspect)) 
#     end
#     ii, jj = ij
#     scaled_ij = (ii, round(Int, jj/aspect))
#     frame[CartesianIndex(scaled_ij)] = bkgd_c
#     name = joinpath(temp_path, @sprintf("%04i.jpg", i))
#     FileIO.save(name, frame)
#     return name
# end
#
# function mkvideo(fps, pps, start_location, width, height, target_width, darker_target, aspect, nsegments, path)
#     ijs = track2right(start_location, width, height, fps, pps)
#
#     row, col = ijs[1]
#     fldr = join((fps, pps, start_location, row, col, width, height, target_width, darker_target, aspect, nsegments), "_")
#     mkdir(joinpath(path, fldr))
#     CSV.write(joinpath(path, fldr, "ijs.csv"), [(; i, j) for (i, j) in ijs])
#
#     mktempdir() do temp_path
#         bkgd_c, target_c = (Gray{N0f8}(darker_target), Gray{N0f8}(~darker_target))
#         blank = fill(bkgd_c, height, width)
#         names = [drawone(blank, ij, target_width ÷ 2, target_c, aspect, temp_path, i, bkgd_c) for (i, ij) in enumerate(ijs)]
#         # w2 = width ÷ aspect
#         segments = round.(Int, range(1, length(ijs), nsegments + 1))
#         duration = 1/fps
#         for (i, (j1, j2)) in enumerate(zip(segments[1:end-1], segments[2:end]))
#             input = joinpath(temp_path, "input$i.txt")
#             open(input, "w") do io
#                 for j in j1:j2
#                     file = names[j]
#                     println(io, """file '$file'
#                             duration $duration""")
#                 end
#             end
#             run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -f concat -safe 0 -i $input -vf setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $(joinpath(path, fldr, "$i.mp4"))`)
#             # run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -f concat -safe 0 -i $input -vf scale=$w2:$height,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $(joinpath(path, fldr, "$i.mp4"))`)
#         end
#     end
# end
#
#
# Threads.@sync for fps in (25, 50), start_location in (:middle, :off), width in (100, 300), height in (100, 300), target_width in (5, 30), darker_target in (true, false), aspect in (0.5, 1, 2), nsegments in (1, 3)
#         # fps, start_location, width, height, target_width, darker_target, aspect, nsegments = (25, :middle, 100, 100, 5, true, 1, 3)
#     Threads.@spawn mkvideo(fps, pps, start_location, width, height, target_width, darker_target, aspect, nsegments, path)
# end
#
# fps, start_location, width, height, target_width, darker_target, aspect, nsegments = (25, :middle, 100, 100, 21, true, 0.5, 3)
#
#
#
#
#
#
# get_coord_fun(row, col, width, fps, aspect) = i -> (row, round(Int, (col - (width/2.5)*sin(2*π*i/fps))/aspect))
# get_coord = get_coord_fun(row, col, width, fps, aspect)
#
# # ijs = [(row, col - (width/2.5)*sin(2*π*i/fps)) for i in 1:seconds*fps]
# using VideoIO
#
# openvideo("output.mp4") do vid
#     img = read(vid)
#     @show size(img)
#     encoder_options = (crf=23, preset="medium")
#     open_video_out("video.mp4", img, framerate=fps, encoder_options=encoder_options) do writer
#         seekstart(vid)
#         i = 0
#         while !eof(vid)
#             read!(vid, img)
#             ij = get_coord(i)
#             frame = draw(img, CirclePointRadius(Point(CartesianIndex(ij)), 2), RGB{N0f8}(1, 0, 0)) 
#             write(writer, frame)
#             i += 1
#         end
#     end
# end
#
#
# #
# #
# #
# #
# # # file = string(join((fps, start_location, width, height, target_width, darker_target, aspect, nsegments), "_"), ".mp4")
# #
# #
# #
# #
# #
# #
# # for (i, (ss, to)) in enumerate(zip(segments[1:end - 1], segments[2:end]))
# #     run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -i $(joinpath(path, file)) -ss $ss -to $to $(joinpath(path, string(file)))`)
# # end
# #
# #
# # return [file]
# #
# #
# # if nsegments > 0
# #     folders = split2folders(temp_path, nsegments)
# #     files = [string(uuid4(), ".mp4") for _ in 1:nsegments]
# #     for (file, folder) in zip(files, folders)
# #         run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $fps -i $(joinpath(folder, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $(joinpath(path, file))`)
# #     end
# #     return files
# # else
# # end
# #     end
# # end
# # end
# #
# #
# #
# #
# #
# #
# #
# #
# #
# #
# #
# #
# # using DataFrames, UUIDs
# # using Printf
# # using ColorTypes, FFMPEG_jll, FixedPointNumbers, ImageDraw, FileIO, ApproxFun
# # using Serialization
# #
# #
# # df = allcombinations("fps" => [25], "start_location" => [(50, 60)], "w" =>  [100], "h" => [100], "target_width" => [5], "darker_target" => [true], "aspect" => [1], "nsegments" =>  [0])
# #
# #
# # aspect = 0.5
# # r, c = (60, 30*aspect)
# # scatterlines(Point2f.(reverse.(track2right(r, c, 100, 100*aspect, 200, aspect))); axis = (; limits = (0,101,0,101), height = 400, width = 400*aspect))
# # scatter!(Point2f(c, r), color = :red)
# #
# #
# #
# # len(θ, b) = b/2*(θ*sqrt(1+θ^2)+asinh(θ))
# #
# # # An Archimedean spiral with 5 loops. It is approximetly `r` at its largest
# # # and has `nframes` coordinates. It has some randomness.
# # function spiral(r, nframes, start_ij)
# #     loops = 5
# #     a = r/loops/2π
# #     f = Fun(θ -> len(θ, a), Interval(0, loops*2π))
# #     θs = [only(roots(f - l)) for l in range(start = 0, length = nframes + 1, stop = maximum(f))][2:end]
# #     ij = Vector{NTuple{2, Int}}(undef, nframes)
# #     for (i, θ) in enumerate(θs)
# #         ij[i] = round.(Int, a*θ .* reverse(sincos(θ)) .+ Tuple(randn(2)))
# #     end
# #     return [i .- ij[1] .+ start_ij for i in ij]
# # end
# #
# # function build_trajectory(r, fps, start_ij)
# #     s = 10 # 10 second long test-videos
# #     ts = range(0, s, step = 1/fps)
# #     nframes = length(ts)
# #     tra = spiral(r, nframes, start_ij)
# #     return ts, tra
# # end
# #
# # function my_partition(xs, nsegments)
# #     n = length(xs)
# #     i1 = round.(Int, range(1, n, nsegments + 1))[1:end-1]
# #     i2 = i1[2:end]# .- 1
# #     push!(i2, n)
# #     return (xs[i1:i2] for (i1, i2) in zip(i1, i2))
# # end
# #
# # function split2folders(path, nsegments)
# #     img_files = readdir(path; join = true)
# #     img_filess = my_partition(img_files, nsegments)
# #     folders = joinpath.(path, string.(1:nsegments))
# #     for (folder, img_files) in zip(folders, img_filess)
# #         mkdir(folder)
# #         for (i, file) in enumerate(img_files)
# #             cp(file, joinpath(folder, @sprintf("%04i.jpg", i)))
# #         end
# #     end
# #     return folders
# # end
# #
# # function trajectory2video(tra, path, fps, w, h, target_width, darker_target, aspect, nsegments)
# #     mktempdir() do temp_path
# #         bkgd_c, target_c = darker_target ? (Gray{N0f8}(1), Gray{N0f8}(0)) : (Gray{N0f8}(0), Gray{N0f8}(1))
# #         blank = fill(Gray{N0f8}(0.5), h, w)
# #         for (i, ij) in enumerate(tra)
# #             frame = draw(blank, CirclePointRadius(Point(CartesianIndex(ij)), target_width ÷ 2), target_c) 
# #             name = joinpath(temp_path, @sprintf("%04i.jpg", i))
# #             FileIO.save(name, frame)
# #         end
# #         w2 = w ÷ aspect
# #         if nsegments > 0
# #             folders = split2folders(temp_path, nsegments)
# #             files = [string(uuid4(), ".mp4") for _ in 1:nsegments]
# #             for (file, folder) in zip(files, folders)
# #                 run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $fps -i $(joinpath(folder, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $(joinpath(path, file))`)
# #             end
# #             return files
# #         else
# #             file = string(uuid4(), ".mp4")
# #             run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $fps -i $(joinpath(temp_path, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $(joinpath(path, file))`)
# #             return [file]
# #         end
# #     end
# # end
# #
# # location2ij(::Missing, h, w) = (h÷2, w÷2) 
# # location2ij(ij::CartesianIndex{2}, _, _) = Tuple(ij)
# # location2ij(xy::NTuple{2, Int}, _, _) = reverse(xy)
# #
# # fix_start_location(::Missing, _) = missing
# # function fix_start_location(ij::CartesianIndex{2}, aspect)
# #     i, j = Tuple(ij)
# #     CartesianIndex(i, round(Int, j / aspect))
# # end
# # function fix_start_location(xy::NTuple{2, Int}, aspect)
# #     j, i = xy
# #     CartesianIndex(i, round(Int, j / aspect))
# # end
# #
# # function scale(ij::CartesianIndex{2}, aspect)
# #     i, j = Tuple(ij)
# #     (i, round(Int, aspect*j))
# # end
# #
# # function build(path, fps, start_location, w, h, target_width, darker_target, aspect, nsegments)
# #     start_ij = location2ij(start_location, h, w)
# #     # build trajectory
# #     r = min(min.(start_ij, (h, w) .- start_ij)...)
# #     ts1, tra = build_trajectory(0.8r, fps, start_ij)
# #     # create a video from the trajectory
# #     file = trajectory2video(tra, path, fps, w, h, target_width, darker_target, aspect, nsegments)
# #     # track the video
# #     start_location = if nsegments > 0
# #         sl = similar(file, Union{Missing, CartesianIndex{2}})
# #         fill!(sl, missing)
# #         sl[1] = fix_start_location(start_location, aspect)
# #         sl
# #     else
# #         fix_start_location(start_location, aspect)
# #     end
# #     if nsegments > 0
# #         tra = vcat(my_partition(tra, nsegments)...)
# #     end
# #     return tra, file
# # end
# #
# # dataset_dir = "tmp"
# # df = allcombinations(DataFrame, "fps" => [25], "start_location" => [(50, 60)], "w" =>  [100], "h" => [100], "target_width" => [5], "darker_target" => [true], "aspect" => [1], "nsegments" =>  [0])
# # # df = allcombinations(DataFrame, "fps" => [25, 50], "start_location" => [missing, CartesianIndex(60, 50), (50, 60)], "w" =>  [100, 150], "h" => [100, 150], "target_width" => [5, 30], "darker_target" => [true, false], "aspect" => [0.5, 1, 1.5], "nsegments" =>  [1, 3])
# # df.file .= Ref(String[])
# # df.track .= Ref(NTuple{2, Int}[])
# #
# #
# # # row = first(eachrow(df))
# # # track, file = build(dataset_dir, row.fps, row.start_location, row.w, row.h, row.target_width, row.darker_target, row.aspect, row.nsegments)
# #
# # Threads.@threads for row in eachrow(df)
# #     row.track, row.file = build(dataset_dir, row.fps, row.start_location, row.w, row.h, row.target_width, row.darker_target, row.aspect, row.nsegments)
# # end
# #
# #
# # serialize(joinpath(dataset_dir, "table"), df)
# #
# #
