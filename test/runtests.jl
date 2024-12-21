using PawsomeTracker
using Test
using Aqua
using ColorTypes, FFMPEG, FixedPointNumbers, ImageDraw, LinearAlgebra, Statistics, VideoIO

function generate(w, h, target_width, start_ij, file)
    framerate = 24
    s = 10 # 10 second long test-videos
    n = s*framerate # number of total frames

    a = 30/n # controls how tight the spiral is
    org = accumulate(range(0, 10π, length = n); init = start_ij) do ij, θ
        cs = cis(θ + randn()/10)
        r = a*θ + randn()/10
        xy = cs * r
        ij .+ round.(Int, (real(xy), imag(xy)))
    end

    blank = ones(Gray{N0f8}, h, w)
    open_video_out(file, eltype(blank), (h, w), framerate=framerate) do writer
        for ij in org
            frame = draw(blank, CirclePointRadius(Point(CartesianIndex(ij)), target_width ÷ 2), zero(eltype(blank))) 
            write(writer, frame)
        end
    end

    return org
end

# compare() = mktempdir() do path
#     file = joinpath(path, "example.mkv")
#     w, h = (200, 150)
#     start_ij = (rand(h ÷ 4 + 1 : 3h ÷ 4 - 1), rand(w ÷ 4 + 1 : 3w ÷ 4 - 1))
#     target_width = rand(5:20)
#     org = generate(w, h, target_width, start_ij, file)
#     start_location = rand((missing, CartesianIndex(start_ij), reverse(start_ij)))
#     _, _, tracked = track(file; start_location)
#     sqrt(mean([LinearAlgebra.norm_sqr(o .- reverse(t)) for (o, t) in zip(org, tracked)]))
# end

compare() = mktempdir() do path

    # path = mktempdir("/home/yakir/PawsomeTracker.jl/test"; cleanup = false)
    file = joinpath(path, "example.mkv")

    aspect = rand(1:3)
    w = rand((100, 150, 200))
    w2 = w ÷ aspect
    w = isodd(w2) ? (w2 + 1)*aspect : w
    h = rand((100, 150, 200))
    i = h÷2 + rand(-20:20)
    j = w÷2 + rand(-20:20)
    start_location = rand((missing, CartesianIndex(i, j), (j, i)))
    start_ij = if ismissing(start_location) 
        (h÷2, w÷2) 
        elseif start_location isa CartesianIndex
            Tuple(start_location)
        else
            reverse(start_location)
        end
    target_width = rand(5:20)
    org = generate(w, h, target_width, start_ij, file)
    file2 = joinpath(path, "example2.mkv")
    w2 = w ÷ aspect
    run(`$(FFMPEG.ffmpeg()) -y -hide_banner -loglevel error -i $file -vf scale=$w2:$h,setsar=$aspect -c:v libx264 $file2`)
    # run(`$(FFMPEG.ffmpeg()) -y -hide_banner -loglevel error -i $file -vf scale=$w2:$h,setdar=1:$a,setsar=1:$a -aspect 1:$a -c:v libx264 $file2`)
    openvideo(VideoIO.aspect_ratio, file2)
    fix_start_location(x) = x
    function fix_start_location(ij::CartesianIndex{2})
        i, j = Tuple(ij)
        CartesianIndex(i, j ÷ aspect)
    end
    _, tracked = track(file2; start_location = fix_start_location(start_location))
    function scale(ij::CartesianIndex{2})
        i, j = Tuple(ij)
        (i, aspect*j)
    end
    sqrt(mean([LinearAlgebra.norm_sqr(o .- scale(t)) for (o, t) in zip(org, tracked)]))



    # file3 = joinpath(path, "example3.mkv")
    # vid = openvideo(file2)
    # open_video_out(file3, RGB.(read(vid)), framerate=24) do writer
    #     for (img, ij) in zip(vid, tracked)
    #         frame = draw(RGB.(img), CirclePointRadius(Point(ij), target_width ÷ 4), RGB(1,0,0))
    #         write(writer, frame)
    #     end
    # end


end

# n = 100
# x = zeros(n)
# Threads.@threads for i in 1:n
#     x[i] = compare()
# end
# @show x


@testset "PawsomeTracker.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(PawsomeTracker; ambiguities = VERSION ≥ VersionNumber("1.7"))
    end
    @testset "random trajectories" begin
        for _ in 1:80
            @test compare() < 2
        end
    end

    @testset "concurrency" begin
        @testset "random trajectories" begin
            Threads.@threads for _ in 1:80
                @test compare() < 2
            end
        end
    end
end
