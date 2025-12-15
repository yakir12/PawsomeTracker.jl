@testsnippet Defaults begin
    fps = 24
    start_location = CartesianIndex(50, 50)
    w = h = 100
    target_width = 10
    darker_target = true
    aspect = 1
    diagnostic_file = nothing
    nsegments = 0
end


@testmodule CommonHelpers begin
    using PawsomeTracker
    using Aqua
    using LinearAlgebra, Statistics, Printf
    using ColorTypes, FFMPEG_jll, FixedPointNumbers, ImageDraw, FileIO, ApproxFun

    len(θ, b) = b / 2 * (θ * sqrt(1 + θ^2) + asinh(θ))

    # An Archimedean spiral with 5 loops. It is approximetly `r` at its largest
    # and has `nframes` coordinates. It has some randomness.
    function spiral(r, nframes, start_ij)
        loops = 5
        a = r / loops / 2π
        f = Fun(θ -> len(θ, a), Interval(0, loops * 2π))
        θs = [only(roots(f - l)) for l in range(start = 0, length = nframes + 1, stop = maximum(f))][2:end]
        ij = Vector{NTuple{2, Int}}(undef, nframes)
        for (i, θ) in enumerate(θs)
            ij[i] = round.(Int, a * θ .* reverse(sincos(θ)) .+ Tuple(randn(2)))
        end
        return [i .- ij[1] .+ start_ij for i in ij]
    end

    function build_trajectory(r, fps, start_ij)
        s = 10 # 10 second long test-videos
        ts = range(0, s, step = 1 / fps)
        nframes = length(ts)
        tra = spiral(r, nframes, start_ij)
        return ts, tra
    end

    function my_partition(xs, nsegments)
        n = length(xs)
        i1 = round.(Int, range(1, n, nsegments + 1))[1:(end - 1)]
        i2 = i1[2:end] # .- 1
        push!(i2, n)
        return (xs[i1:i2] for (i1, i2) in zip(i1, i2))
    end

    function split2folders(path, nsegments)
        img_files = readdir(path; join = true)
        img_filess = my_partition(img_files, nsegments)
        folders = joinpath.(path, string.(1:nsegments))
        for (folder, img_files) in zip(folders, img_filess)
            mkdir(folder)
            for (i, file) in enumerate(img_files)
                cp(file, joinpath(folder, @sprintf("%04i.jpg", i)))
            end
        end
        return folders
    end

    function trajectory2video(tra, path, fps, w, h, target_width, darker_target, aspect, nsegments)
        bkgd_c, target_c = darker_target ? (Gray{N0f8}(1), Gray{N0f8}(0)) : (Gray{N0f8}(0), Gray{N0f8}(1))
        blank = fill(Gray{N0f8}(0.5), h, w)
        for (i, ij) in enumerate(tra)
            frame = draw(blank, CirclePointRadius(Point(CartesianIndex(ij)), target_width ÷ 2), target_c)
            name = joinpath(path, @sprintf("%04i.jpg", i))
            FileIO.save(name, frame)
        end
        w2 = w ÷ aspect
        if nsegments > 0
            folders = split2folders(path, nsegments)
            files = joinpath.(path, string.(1:nsegments, ".mp4"))
            for (file, folder) in zip(files, folders)
                run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $fps -i $(joinpath(folder, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $file`)
            end
            return files
        else
            file = joinpath(path, "example.mp4")
            run(`$(FFMPEG_jll.ffmpeg()) -loglevel error -framerate $fps -i $(joinpath(path, "%04d.jpg")) -vf scale=$w2:$h,setsar=$aspect -c:v libx264 -r $fps -pix_fmt yuv420p $file`)
            return file
        end
    end

    location2ij(::Missing, h, w) = (h ÷ 2, w ÷ 2)
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
        (i, round(Int, aspect * j))
    end

    function compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
        mktempdir() do path
            start_ij = location2ij(start_location, h, w)
            # build trajectory
            r = min(min.(start_ij, (h, w) .- start_ij)...)
            ts1, tra = build_trajectory(0.8r, fps, start_ij)
            # create a video from the trajectory
            file = trajectory2video(tra, path, fps, w, h, target_width, darker_target, aspect, nsegments)
            # @show 4
            # track the video
            start_location = if nsegments > 0
                sl = similar(file, Union{Missing, CartesianIndex{2}})
                fill!(sl, missing)
                sl[1] = fix_start_location(start_location, aspect)
                sl
            else
                # @show 5
                fix_start_location(start_location, aspect)
            end
            # @show 6
            ts2, tracked = track(file; fps, start_location, darker_target, diagnostic_file)
            # @show 7
            if nsegments > 0
                tra = vcat(my_partition(tra, nsegments)...)
            end
            # compare the tracked trajectory to the original one
            return sqrt(mean([LinearAlgebra.norm_sqr(o .- scale(t, aspect)) for (o, t) in zip(tra, tracked)]))
        end
    end
end

# @testitem "Diagnostic file generation" setup = [Defaults] begin
#     @test true
@testitem "Diagnostic file generation" setup = [CommonHelpers, Defaults] begin
    mktempdir() do temp_path
        diagnostic_file = joinpath(temp_path, "test.ts")
        CommonHelpers.compare(fps, start_location, w, h, target_width, darker_target, aspect, diagnostic_file, nsegments)
        @test isfile(diagnostic_file)
    end
end
