using PawsomeTracker
using Test
using Aqua

using LinearAlgebra, Statistics
using VideoIO, ImageDraw, ColorTypes, FixedPointNumbers

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
    start_xy = rand(Bool) ? reverse(start_ij) : missing
    _, tracked = track(file; start_xy)
    sqrt(mean([LinearAlgebra.norm_sqr(o .- reverse(t)) for (o, t) in zip(org, tracked)]))
end

@testset "PawsomeTracker.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(PawsomeTracker; ambiguities = VERSION ≥ VersionNumber("1.7"))
    end
    @testset "multiple random trajectories" begin
        for _ in 1:100
            @test compare() < 1
        end
    end

    @testset "multiple random concurrent trajectories" begin
        Threads.@threads for _ in 1:100
            @test compare() < 1
        end
    end
end
