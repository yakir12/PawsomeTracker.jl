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

compare() = mktempdir() do path
    file = joinpath(path, "example.mkv")
    w, h = (200, 150)
    start_ij = (rand(h ÷ 4 + 1 : 3h ÷ 4 - 1), rand(w ÷ 4 + 1 : 3w ÷ 4 - 1))
    target_width = rand(5:20)
    org = generate(w, h, target_width, start_ij, file)
    _, _, tracked = track(file)
    sqrt(mean([LinearAlgebra.norm_sqr(o .- reverse(t)) for (o, t) in zip(org, tracked)]))
end

compare_aspect() = mktempdir() do path
    file = joinpath(path, "example.mkv")
    w, h = (200, 200)
    start_ij = (75, 50)
    target_width = rand(5:20)
    org = generate(w, h, target_width, start_ij, file)
    file2 = joinpath(path, "example2.mkv")
    a = 2
    w2 = w ÷ a
    run(`$(FFMPEG.ffmpeg()) -hide_banner -loglevel error -i $file -vf scale=$w2:$h,setdar=1:$a,setsar=1:$a -aspect 1:1 -c:v libx264 $file2`)
    _, _, tracked = track(file2; start_xy = reverse(start_ij))
    sqrt(mean([LinearAlgebra.norm_sqr(o .- reverse(t)) for (o, t) in zip(org, tracked)]))
end



@testset "PawsomeTracker.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(PawsomeTracker; ambiguities = VERSION ≥ VersionNumber("1.7"))
    end
    @testset "multiple random trajectories" begin
        for _ in 1:10
            @test compare() < 1
        end
    end

    @testset "video with aspect ration ≠ 1" begin
        for _ in 1:10
            @test compare_aspect() < 2
        end
    end

    @testset "concurrency" begin
        @testset "multiple random trajectories" begin
            Threads.@threads for _ in 1:10
                @test compare() < 1
            end
        end

        @testset "video with aspect ration ≠ 1" begin
            Threads.@threads for _ in 1:10
                @test compare_aspect() < 2
            end
        end

    end
end
