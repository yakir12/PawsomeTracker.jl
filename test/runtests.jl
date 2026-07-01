using Revise
using PawsomeTracker
using Test
using CSV
using Statistics
using LinearAlgebra

function parse_start_location(txt, nsegments, row, col)
    if txt == "middle"
        return fill(missing, nsegments)
    elseif txt == "off"
        start_location = Vector{Union{Missing, NTuple{2, Int}}}(undef, nsegments)
        fill!(start_location, missing)
        start_location[1] = (row, col)
        return start_location
    else
        error("what...")
    end
end

adjust_start_location(::Missing, _) = missing

function adjust_start_location(ij::CartesianIndex{2}, aspect)
    i, j = Tuple(ij)
    CartesianIndex(i, round(Int, j / aspect))
end
function adjust_start_location(xy::NTuple{2, Int}, aspect)
    j, i = xy
    (i, round(Int, j / aspect))
end

function scale(ij::CartesianIndex{2}, aspect)
    i, j = Tuple(ij)
    CartesianIndex((i, round(Int, aspect*j)))
end

# function compare(a, b, aspect)
#     sqrt(mean([LinearAlgebra.norm_sqr(Tuple(ai) .- Tuple(scale(bi, aspect))) for (ai, bi) in zip(a, b)]))
# end

function compare(data, fun)
    sqrt(mean([LinearAlgebra.norm_sqr(Tuple(x) .- fun(i)) for (i, x) in enumerate(data)]))
end

get_coord_fun(row, col, width, fps, aspect) = i -> (row + 1, round(Int, (col - (width/2.5)*sin(0.5*π*(i - 1)/fps))/aspect + 1))

dataset_dir = "../utils/vids"

# Threads.@threads 
for dir in readdir(dataset_dir)

    # dir = collect(readdir(dataset_dir))[1]
    dir = "25_middle_150_150_300_300_30_false_0.5_3"
    dir = "25_off_225_105_300_300_30_false_0.5_1"
    # dir = "25_middle_50_50_100_100_5_false_0.5_1"

    fps, start_location_type, row, col, width, height, target_width, darker_target, aspect, nsegments = split(dir, "_")
    fps, row, col, width, target_width, darker_target, aspect, nsegments = (parse(Int, fps), parse(Int, row), parse(Int, col), parse(Int, width), parse(Int, target_width), parse(Bool, darker_target), parse(Float64, aspect), parse(Int, nsegments))

    get_coord = get_coord_fun(row, col, width, fps, aspect)

    start_location = parse_start_location(start_location_type, nsegments, row, col)
    start_location = adjust_start_location.(start_location, aspect)
    all_files = readdir(joinpath(dataset_dir, dir); join = true)
    files = filter(==(".mp4") ∘ last ∘ splitext, all_files)
    # csv_file = only(filter(==(".csv") ∘ last ∘ splitext, all_files))
    # tbl = CSV.File(csv_file)
    # ijs = [CartesianIndex(row.i, row.j) for row in tbl]
    if nsegments == 1
        files = only(files)
        start_location = only(start_location)
    end

    @testset "fps = $fps start_location = $start_location_type  width = $width height = $height target_width = $target_width darker_target = $darker_target aspect = $aspect nsegments = $nsegments" begin

        _, ijs2 = track(files; start_location, target_width, darker_target)#, window_size = 50)
        # [Tuple(ij) .- get_coord(i) for (i, ij) in enumerate(ijs2)]

        @test compare(ijs2, get_coord) < 1

    end
end


using VideoIO, ImageDraw, ColorTypes, FixedPointNumbers

openvideo(files) do vid
    img = read(vid)
    encoder_options = (crf=23, preset="medium")
    open_video_out("video.mp4", img, framerate=fps, encoder_options=encoder_options) do writer
        seekstart(vid)
        i = 0
        while !eof(vid)
            i += 1
            read!(vid, img)
            ij = get_coord(i)
            frame = draw(img, CirclePointRadius(Point(CartesianIndex(ij)), 2), RGB{N0f8}(1, 0, 0)) 
            write(writer, frame)
        end
    end
end




# using StaticArrays
# using Aqua
# using LinearAlgebra, Statistics, Printf
# using ColorTypes, FFMPEG_jll, FixedPointNumbers, ImageDraw, FileIO, ApproxFun



# len(θ, b) = b/2*(θ*sqrt(1+θ^2)+asinh(θ))
#
# # An Archimedean spiral with 5 loops. It is approximetly `r` at its largest
# # and has `nframes` coordinates. It has some randomness.
# function spiral(r, nframes, start_ij)
#     loops = 5
#     a = r/loops/2π
#     f = Fun(θ -> len(θ, a), Interval(0, loops*2π))
#     θs = [only(roots(f - l)) for l in range(start = 0, length = nframes + 1, stop = maximum(f))][2:end]
#     ij = Vector{NTuple{2, Int}}(undef, nframes)
#     for (i, θ) in enumerate(θs)
#         ij[i] = round.(Int, a*θ .* reverse(sincos(θ)) .+ Tuple(randn(2)))
#     end
#     return [i .- ij[1] .+ start_ij for i in ij]
# end
#
# function build_trajectory(r, fps, start_ij)
#     s = 10 # 10 second long test-videos
#     ts = range(0, s, step = 1/fps)
#     nframes = length(ts)
#     tra = spiral(r, nframes, start_ij)
#     return ts, tra
# end
#
# function my_partition(xs, nsegments)
#     n = length(xs)
#     i1 = round.(Int, range(1, n, nsegments + 1))[1:end-1]
#     i2 = i1[2:end]# .- 1
#     push!(i2, n)
#     return (xs[i1:i2] for (i1, i2) in zip(i1, i2))
# end
#
# function split2folders(path, nsegments)
#     img_files = readdir(path; join = true)
#     img_filess = my_partition(img_files, nsegments)
#     folders = joinpath.(path, string.(1:nsegments))
#     for (folder, img_files) in zip(folders, img_filess)
#         mkdir(folder)
#         for (i, file) in enumerate(img_files)
#             cp(file, joinpath(folder, @sprintf("%04i.jpg", i)))
#         end
#     end
#     return folders
# end
#
# function trajectory2video(tra, path, fps, w, h, target_width, darker_target, aspect, nsegments)
#     bkgd_c, target_c = darker_target ? (Gray{N0f8}(1), Gray{N0f8}(0)) : (Gray{N0f8}(0), Gray{N0f8}(1))
#     blank = fill(Gray{N0f8}(0.5), h, w)
#     for (i, ij) in enumerate(tra)
#         frame = draw(blank, CirclePointRadius(Point(CartesianIndex(ij)), target_width ÷ 2), target_c) 
#         name = joinpath(path, @sprintf("%04i.jpg", i))
#         FileIO.save(name, frame)
#     end
#     w2 = w ÷ aspect
#     if nsegments > 0
#         folders = split2folders(path, nsegments)
#         files = joinpath.(path, string.(1:nsegments, ".mp4"))
#         for (file, folder) in zip(files, folders)
#             run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $fps -i $(joinpath(folder, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $file`)
#         end
#         return files
#     else
#         file = joinpath(path, "example.mp4")
#         run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $fps -i $(joinpath(path, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $file`)
#         return file
#     end
# end
#
# location2ij(::Missing, h, w) = (h÷2, w÷2) 
# location2ij(ij::CartesianIndex{2}, _, _) = Tuple(ij)
# location2ij(xy::NTuple{2, Int}, _, _) = reverse(xy)
#
# fix_start_location(::Missing, _) = missing
# function fix_start_location(ij::CartesianIndex{2}, aspect)
#     i, j = Tuple(ij)
#     CartesianIndex(i, round(Int, j / aspect))
# end
# function fix_start_location(xy::NTuple{2, Int}, aspect)
#     j, i = xy
#     CartesianIndex(i, round(Int, j / aspect))
# end
#
# function scale(ij::CartesianIndex{2}, aspect)
#     i, j = Tuple(ij)
#     (i, round(Int, aspect*j))
# end
#
# function compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
#     mktempdir() do path
#         start_ij = location2ij(start_location, h, w)
#         # build trajectory
#         r = min(min.(start_ij, (h, w) .- start_ij)...)
#         ts1, tra = build_trajectory(0.8r, fps, start_ij)
#         # create a video from the trajectory
#         file = trajectory2video(tra, path, fps, w, h, target_width, darker_target, aspect, nsegments)
#         # track the video
#         start_location = if nsegments > 0
#             sl = similar(file, Union{Missing, CartesianIndex{2}})
#             fill!(sl, missing)
#             sl[1] = fix_start_location(start_location, aspect)
#             sl
#         else
#             fix_start_location(start_location, aspect)
#         end
#         ts2, tracked = track(file; fps, start_location, darker_target, diagnostic_file)
#         if nsegments > 0
#             tra = vcat(my_partition(tra, nsegments)...)
#         end
#         # compare the tracked trajectory to the original one
#         return sqrt(mean([LinearAlgebra.norm_sqr(o .- scale(t, aspect)) for (o, t) in zip(tra, tracked)]))
#     end
# end



@testset "PawsomeTracker.jl" begin
    # defaults
    fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments = (24, CartesianIndex(50, 50), 100, 100, 10, true, 1, nothing, 0)

    # mktempdir() do temp_path
    #     @testset "diagnostic file is $diagnostic_file" for diagnostic_file in (nothing, joinpath(temp_path, "test.ts"))
    #         ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
    #         @test isnothing(diagnostic_file) || isfile(diagnostic_file)
    #         @test ϵ < 1
    #     end
    # end

    @testset "framerate: $fps" for fps in (25, 50)
        ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
        @test ϵ < 1
    end

    # @testset "darker target: $darker_target" for darker_target in (true, false)
    #     ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
    #     @test ϵ < 1
    # end
    #
    # @testset "start locationt $start_location" for start_location in (missing, CartesianIndex(60, 50), (50, 60))
    #     ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
    #     @test ϵ < 1
    # end
    #
    # @testset "target width: $target_width" for target_width in (5, 20)
    #     ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
    #     @test ϵ < 1
    # end
    #
    # @testset "segmented video files: $nsegments" for nsegments in (0, 1, 3)
    #     ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
    #     @test ϵ < 1
    # end
    #
    # @testset "width: $w" for w in (100, 150)
    #     @testset "height: $h" for h in (100, 150)
    #         @testset "aspect: $aspect" for aspect in (0.5, 1, 1.5)
    #             ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
    #             @test ϵ < 1
    #         end
    #     end
    # end
    #
    # @testset "threaded" begin
    #     n = Threads.nthreads()
    #     if n > 1
    #         Threads.@threads for _ in 1:2n # twice the number of threads
    #             ϵ = compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
    #             @test ϵ < 1
    #         end
    #     else
    #         @warn "There is only one thread. Skipping this test..."
    #     end
    # end
    #
    # @testset "Code quality (Aqua.jl)" begin
    #     Aqua.test_all(PawsomeTracker; ambiguities = VERSION ≥ VersionNumber("1.7"))
    # end
end
