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



