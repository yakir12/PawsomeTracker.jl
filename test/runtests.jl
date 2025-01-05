using PawsomeTracker
using Test
using Aqua
using LinearAlgebra, Statistics, Printf
using ColorTypes, FFMPEG_jll, FixedPointNumbers, ImageDraw, FileIO

function build_trajectory(framerate, start_ij)
    s = 10 # 10 second long test-videos
    n = s*framerate # number of total frames
    a = 20/n # controls how tight the spiral is
    tra = Vector{NTuple{2, Int}}(undef, n)
    accumulate!(tra, range(0, 10π, length = n); init = start_ij) do ij, θ
        cs = cis(θ + randn()/10)
        r = a*θ + randn()/10
        xy = cs * r
        ij .+ round.(Int, (real(xy), imag(xy)))
    end
    return tra
end

function trajectory2video(tra, path, framerate, w, h, target_width, darker_target, aspect)
    bkgd_c, target_c = darker_target ? (Gray{N0f8}(1), Gray{N0f8}(0)) : (Gray{N0f8}(0), Gray{N0f8}(1))
    blank = fill(bkgd_c, h, w)
    for (i, ij) in enumerate(tra)
        frame = draw(blank, CirclePointRadius(Point(CartesianIndex(ij)), target_width ÷ 2), target_c) 
        name = joinpath(path, @sprintf("%04i.jpg", i))
        FileIO.save(name, frame)
    end
    w2 = w ÷ aspect
    file = joinpath(path, "example.mp4")
    run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $framerate -i $(joinpath(path, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $framerate -pix_fmt yuv420p $file`)
    return file
end

location2ij(::Missing, h, w) = (h÷2, w÷2) 
location2ij(ij::CartesianIndex{2}, _, _) = Tuple(ij)
location2ij(xy::NTuple{2, Int}, _, _) = reverse(xy)

fix_start_location(::Missing, _) = missing
function fix_start_location(ij::CartesianIndex{2}, aspect)
    i, j = Tuple(ij)
    CartesianIndex(i, round(Int, j / aspect))
end
function fix_start_location(xy::NTuple{2, Int}, aspect)
    j, i = xy
    CartesianIndex(i, round(Int, j / aspect))
end

function scale(ij::CartesianIndex{2}, aspect)
    i, j = Tuple(ij)
    (i, round(Int, aspect*j))
end

function compare(framerate, start_location, w, h, target_width, darker_target, aspect)
    mktempdir() do path
        start_ij = location2ij(start_location, h, w)
        # build trajectory
        tra = build_trajectory(framerate, start_ij)
        # create a video from the trajectory
        file = trajectory2video(tra, path, framerate, w, h, target_width, darker_target, aspect)
        # track the video
        _, tracked = track(file; start_location = fix_start_location(start_location, aspect), darker_target)
        # compare the tracked trajectory to the original one
        return sqrt(mean([LinearAlgebra.norm_sqr(o .- scale(t, aspect)) for (o, t) in zip(tra, tracked)]))
    end
end

# path = mktempdir("/home/yakir/tmp/PawsomeTracker.jl/test"; cleanup = false)
# framerate = 25
# start_location = missing
# w, h = (100, 150)
# start_ij = location2ij(start_location, h, w)
# target_width = 10
# darker_target = true
# aspect = 1

@testset "PawsomeTracker.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(PawsomeTracker; ambiguities = VERSION ≥ VersionNumber("1.7"))
    end
    @testset "framerate: $framerate" for framerate in (10, 30)
        @testset "width: $w" for w in (100, 150)
            @testset "height: $h" for h in (100, 150)
                @testset "target width: $target_width" for target_width in (5, 20)
                    @testset "darker target: $darker_target" for darker_target in (true, false)
                        @testset "aspect: $aspect" for aspect in 0.5:0.5:1.5
                            @testset "start locationt $start_location" for start_location in (missing, CartesianIndex(60, 50), (50, 60))
                                ϵ = compare(framerate, start_location, w, h, target_width, darker_target, aspect)
                                @test ϵ < 1
                            end
                        end
                    end
                end
            end
        end
    end
end



#
#
# function generate(path, file, w, h, target_width, start_ij, darker_target, aspect)
#     framerate = 24
#     bkgd_c, target_c = darker_target ? (Gray{N0f8}(1), Gray{N0f8}(0)) : (Gray{N0f8}(0), Gray{N0f8}(1))
#     blank = fill(bkgd_c, h, w)
#     for (i, ij) in enumerate(org)
#         frame = draw(blank, CirclePointRadius(Point(CartesianIndex(ij)), target_width ÷ 2), target_c) 
#         name = joinpath(path, @sprintf("%04i.jpg", i))
#         FileIO.save(name, frame)
#     end
#     w2 = w ÷ aspect
#     run(`$(FFMPEG_jll.ffmpeg()) -framerate $framerate -i $(joinpath(path, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $framerate -pix_fmt yuv420p $file`)
#     return org
# end
#
# # compare() = mktempdir() do path
# #     file = joinpath(path, "example.mkv")
# #     w, h = (200, 150)
# #     start_ij = (rand(h ÷ 4 + 1 : 3h ÷ 4 - 1), rand(w ÷ 4 + 1 : 3w ÷ 4 - 1))
# #     target_width = rand(5:20)
# #     org = generate(w, h, target_width, start_ij, file)
# #     start_location = rand((missing, CartesianIndex(start_ij), reverse(start_ij)))
# #     _, _, tracked = track(file; start_location)
# #     sqrt(mean([LinearAlgebra.norm_sqr(o .- reverse(t)) for (o, t) in zip(org, tracked)]))
# # end
#
#
# compare() = mktempdir() do path
#
#     path = mktempdir("/home/yakir/tmp/PawsomeTracker.jl/test"; cleanup = false)
#
#     aspect = rand(1:3)
#     w = rand((100, 150, 200))
#     w2 = w ÷ aspect
#     w = isodd(w2) ? (w2 + 1)*aspect : w
#     h = rand((100, 150, 200))
#     i = h÷2 + rand(-20:20)
#     j = w÷2 + rand(-20:20)
#     start_location = rand((missing, CartesianIndex(i, j), (j, i)))
#     start_ij = if ismissing(start_location) 
#         (h÷2, w÷2) 
#     elseif start_location isa CartesianIndex
#         Tuple(start_location)
#     else
#         reverse(start_location)
#     end
#     target_width = rand(5:20)
#     darker_target = rand(Bool)
#     file = joinpath(path, "example.mp4")
#     org = generate(path, file, w, h, target_width, start_ij, darker_target)
#
#     # file2 = joinpath(path, "example2.mkv")
#     # w2 = w ÷ aspect
#     # run(`$(FFMPEG_jll.ffmpeg()) -y -hide_banner -loglevel error -i $file -vf scale=$w2:$h,setsar=$aspect -c:v libx264 $file2`)
#     # # run(`$(FFMPEG.ffmpeg()) -y -hide_banner -loglevel error -i $file -vf scale=$w2:$h,setdar=1:$a,setsar=1:$a -aspect 1:$a -c:v libx264 $file2`)
#     # @assert aspect == PawsomeTracker.get_sar(file)
#     _, tracked = track(file; start_location = fix_start_location(start_location, aspect), darker_target)
#     sqrt(mean([LinearAlgebra.norm_sqr(o .- scale(t)) for (o, t) in zip(org, tracked)]))
#
#
#
#     # file3 = joinpath(path, "example3.mkv")
#     # vid = openvideo(file2)
#     # open_video_out(file3, RGB.(read(vid)), framerate=24) do writer
#     #     for (img, ij) in zip(vid, tracked)
#     #         frame = draw(RGB.(img), CirclePointRadius(Point(ij), target_width ÷ 4), RGB(1,0,0))
#     #         write(writer, frame)
#     #     end
#     # end
#
#
# end
#
# # n = 100
# # x = zeros(n)
# # Threads.@threads for i in 1:n
# #     x[i] = compare()
# # end
# # @show x
# # create trajectory
# # create video
# # track
# # compare
#
#
# @testset "PawsomeTracker.jl" begin
#     @testset "Code quality (Aqua.jl)" begin
#         Aqua.test_all(PawsomeTracker; ambiguities = VERSION ≥ VersionNumber("1.7"))
#     end
#     @testset "random trajectories" begin
#         for _ in 1:20
#             @test compare() < 2
#         end
#     end
#
#     @testset "concurrency" begin
#         @testset "random trajectories" begin
#             n = 20
#             rs = zeros(n)
#             Threads.@threads for i in 1:n
#                 rs[i] = compare()
#             end
#             for r in rs
#                 @test r < 2
#             end
#         end
#     end
# end
