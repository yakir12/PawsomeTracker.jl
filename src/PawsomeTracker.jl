module PawsomeTracker

using ImageFiltering: Kernel, imfilter!, Algorithm, NoPad
using OffsetArrays: OffsetMatrix
using PaddedViews: PaddedView
using StatsBase: mode, median
using FFMPEG: exe, ffprobe, ffmpeg
using VideoIO: openvideo, AV_PIX_FMT_GRAY8, aspect_ratio, open_video_out, VideoWriter, close_video_out!, framerate, skipframes, gettime, get_duration
using ImageDraw: draw!, CirclePointRadius, Path
using FreeTypeAbstraction: renderstring!, FTFont
using ColorTypes: Gray
using FixedPointNumbers: N0f8
using ImageTransformations: imresize!, warp
using RelocatableFolders: @path
using ComputationalResources: CPUThreads
using DataStructures: CircularBuffer
using AprilTags: AprilTagDetector
using StaticArrays: SVector, push, SMatrix, pop, SDiagonal
using OpenCV
using CoordinateTransformations: PerspectiveMap, LinearMap
using ImageCore: clamp01
using LinearAlgebra: I
using OhMyThreads: tcollect

const FACE = Ref{FTFont}()
const DEFAULT_MAX_DURATION_SECONDS = 86399.999  # 24 hours minus 1 millisecond
const RowCol = SVector{2, Float32}

# Global limiter on concurrent ffmpeg reads, shared by every `_frame_at` call (and thus by
# VerifyCalibrations, which reads through `Rectifications.get_corners`). Bounds simultaneous
# opens against the (CIFS/network) share so a burst of nested `tmap` tasks can't trip EAGAIN
# ("Resource temporarily unavailable"). A single global limiter is what composes across the
# nested tmaps — per-call `ntasks` limits would multiply. Tune via `set_read_limit!` or the
# `RECTIFICATIONS_READ_LIMIT` env var (read at `__init__`).
const READ_SEM = Ref{Base.Semaphore}()
set_read_limit!(n::Integer) = (READ_SEM[] = Base.Semaphore(n); Int(n))
read_limit() = READ_SEM[].sem_size

# ffmpeg/ffprobe commands are built by interpolating the *called* `FFMPEG.ffmpeg()` /
# `FFMPEG.ffprobe()` (the non-do-block form): each returns a `Cmd` with the absolute executable
# path and the adjusted `PATH`/`LD_LIBRARY_PATH` baked in via `setenv`, and that env survives
# interpolation into the surrounding `Cmd`. Unlike the deprecated `ffmpeg() do ... end` form it
# never mutates the process-global `ENV`, so it composes safely under the nested `tmap`
# concurrency — no snapshot, no `addenv`, no env race (which previously grew `LD_LIBRARY_PATH`
# without bound until a spawn died with E2BIG). See `_cmd` / `_probe`.

function __init__()
    # Concurrency is bounded only by the share itself; benchmarks against the CIFS mount plateau
    # around 12-24 concurrent reads (vs ~6 here historically).
    set_read_limit!(parse(Int, get(ENV, "RECTIFICATIONS_READ_LIMIT", "12")))

    assets = @path joinpath(@__DIR__, "../assets")
    return FACE[] = FTFont(joinpath(assets, "TeXGyreHerosMakie-Regular.otf"))
end

export track

include("diagnose.jl")


function _get_wh(file)
    s = read(`$(ffprobe()) -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $file`, String)
    w, h = split(strip(s), ',')
    return (parse(Int, w), parse(Int, h))
end

# Read one frame, retrying transient failures. EAGAIN ("Resource temporarily unavailable") from
# the CIFS share is transient by definition, so a few backoff retries ride out residual blips even
# under the concurrency limit. A persistent failure still rethrows after the last try.
function _read_frame(cmd; tries = 4)
    for i in 1:tries
        try
            return read(cmd)
        catch e
            i == tries && rethrow()
            sleep(0.2 * 2^(i - 1))          # 0.2s, 0.4s, 0.8s backoff
        end
    end
end

_cmd(file, t) = `$(ffmpeg()) -hide_banner -loglevel error -ss $t -i $file -frames:v 1 -f rawvideo -pix_fmt gray pipe:1`

function _frame_at(file, t, w, h)

    cmd = _cmd(file, t)
    buf = Base.acquire(() -> _read_frame(cmd), READ_SEM[])   # bound concurrent opens against the share
    return float.(permutedims(reshape(buf, w, h)))
end

function get_bkgd(file, start, stop)
    w, h = _get_wh(file)
    n = 20
    ts = range(start, stop, length = n)
    imgs = tcollect(_frame_at(file, t, w, h) for t in ts)
    dropdims(median(stack(imgs); dims=3); dims=3)
end

function get_framerate(file)
    vid_fps = openvideo(framerate, file)
    !isinf(vid_fps) && return vid_fps
    txt = exe(` -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 $file`, command=ffprobe, collect=true)
    parse(Rational{Int}, only(txt))
end

get_sigma(target_width) = target_width / 2sqrt(2log(2))

# struct Tracker4Big
#     sz::Tuple{Int64, Int64}
#     radii::Tuple{Int64, Int64}
#     kernel::OffsetMatrix{Float64, Matrix{Float64}}
#     img::PaddedView{Gray{N0f8}, 2, Tuple{Base.IdentityUnitRange{UnitRange{Int64}}, Base.IdentityUnitRange{UnitRange{Int64}}}, PermutedDimsArray{Gray{N0f8}, 2, (2, 1), (2, 1), Matrix{Gray{N0f8}}}}
#     buff::OffsetMatrix{Float64, Matrix{Float64}}
#
#     function Tracker4Big(_img, target_width, window_size, darker_target)
#         sz = size(_img)
#         σ = get_sigma(target_width)
#         direction = darker_target ? -1 : +1
#         kernel = direction * Kernel.DoG(σ)
#         radii = window_size .÷ 2
#         h = radii .+ size(kernel)
#         pad_indices = UnitRange.(1 .- h, sz .+ h)
#         fillvalue = mode(_img)
#         img = PaddedView(fillvalue, _img, pad_indices)
#         _buff = Matrix{Float64}(undef, length.(pad_indices))
#         buff = OffsetMatrix(_buff, pad_indices)
#         return new(sz, radii, kernel, img, buff)
#     end
# end
#
# function (trckr::Tracker4Big)(guess::NTuple{2, Int})
#     window_indices = UnitRange.(guess .- trckr.radii, guess .+ trckr.radii)
#     roi = view(trckr.buff, window_indices...)
#     imresize!(resized.data, roi)
#     imfilter!(CPUThreads(Algorithm.FIR()), trckr.buff, trckr.img, trckr.kernel, NoPad(), window_indices)
#     v = view(trckr.buff, window_indices...)
#     _, ij = findmax(v)
#     guess = getindex.(parentindices(v), Tuple(ij))
#     return min.(max.(guess, (1, 1)), trckr.sz)
# end


struct Tracker
    sz::Tuple{Int64, Int64}
    radii::Tuple{Int64, Int64}
    kernel::OffsetMatrix{Float64, Matrix{Float64}}
    img::PaddedView{Gray{N0f8}, 2, Tuple{Base.IdentityUnitRange{UnitRange{Int64}}, Base.IdentityUnitRange{UnitRange{Int64}}}, PermutedDimsArray{Gray{N0f8}, 2, (2, 1), (2, 1), Matrix{Gray{N0f8}}}}
    buff::OffsetMatrix{Float64, Matrix{Float64}}
    white_point::Float64
    bkgd

    function Tracker(_img, target_width, window_size, darker_target, sar, white_point, bkgd)
        sz = size(_img)
        σ = get_sigma(target_width)
        direction = darker_target ? -1 : +1
        kernel = direction * Kernel.DoG((σ/sar, σ))
        radii = window_size .÷ 2
        h = radii .+ size(kernel)
        pad_indices = UnitRange.(1 .- h, sz .+ h)
        fillvalue = mode(_img)
        img = PaddedView(fillvalue, _img, pad_indices)
        _buff = Matrix{Float64}(undef, length.(pad_indices))
        buff = OffsetMatrix(_buff, pad_indices)
        return new(sz, radii, kernel, img, buff, white_point, bkgd)
    end
end

function (trckr::Tracker)(guess::NTuple{2, Int})
    window_indices = UnitRange.(guess .- trckr.radii, guess .+ trckr.radii)

    if !isone(trckr.white_point)
        trckr.img.data .= clamp01.(trckr.img.data ./ trckr.white_point)
    end

    # trckr.img.data[window_indices...] .-= trckr.bkgd[window_indices...]

    imfilter!(CPUThreads(Algorithm.FIR()), trckr.buff, trckr.img, trckr.kernel, NoPad(), window_indices)
    v = view(trckr.buff, window_indices...)
    _, ij = findmax(v)
    guess = getindex.(parentindices(v), Tuple(ij))
    return min.(max.(guess, (1, 1)), trckr.sz)
end

function guess_window_size(target_width)
    σ = get_sigma(target_width)
    l = 4ceil(Int, σ) + 1 # calculates the default window size
    return l
end

function fix_window_size(wh::NTuple{2, Int}) 
    w, h = wh
    if !isodd(w)
        w += 1
    end
    if !isodd(h)
        h += 1
    end
    return (h, w)
end

function fix_window_size(l::Int) 
    if !isodd(l)
        l += 1
    end
    return (l, l)
end

function get_guess(start_index::CartesianIndex{2}, _, _, _)
    guess = Tuple(start_index)
    return guess
end

function get_guess(start_xy::NTuple{2, Int}, vid, _, sar)
    x, y = start_xy
    guess = round.(Int, (y, x / sar))
    return guess
end

function get_guess(::Missing, _, img, _)
    sz = size(img)
    guess = sz .÷ 2
    return guess
end

function get_start_ij_and_tracker(start_location, vid, img, target_width, window_size, darker_target, _, white_point, bkgd)
    sar = aspect_ratio(vid)
    guess = get_guess(start_location, vid, img, sar)
    trckr = Tracker(img, target_width, window_size, darker_target, sar, white_point, bkgd)
    ij = trckr(guess)
    return trckr, ij
end

function get_start_ij_and_tracker(start_location::Missing, vid, img, target_width, window_size, darker_target, initial_search_factor, white_point, bkgd)
    sar = aspect_ratio(vid)
    guess = get_guess(start_location, vid, img, sar)
    sz = size(img)
    window_size2 = sz .÷ 4 # this greatly affects processing time!
    trckr = Tracker(img, target_width, window_size2, darker_target, sar, white_point, bkgd) # initial auto-detection pass
    ij = trckr(guess)
    trckr = Tracker(img, target_width, window_size, darker_target, sar, white_point, bkgd)
    return trckr, ij
end

"""
    track(file; start, stop, target_width, start_location, window_size, darker_target, fps, diagnostic_file)

Use a Difference of Gaussian (DoG) filter to track a target in a video `file`. 
- `start`: start tracking after `start` seconds. Defaults to 0.
- `stop`: stop tracking at `stop` seconds.  Defaults to 86399.999 seconds (24 hours minus one millisecond).
- `target_width`: the full width of the target (diameter, not radius). It is used as the FWHM of the center Gaussian in the DoG filter. Arbitrarily defaults to 25 pixels.
- `start_location`: one of the following:
    1. `missing`: the target will be detected in a large (quarter the frame size) window centered at the frame.
    2. `CartesianIndex{2}`: the Cartesian index (into the image matrix) indicating where the target is at `start`. Note that when the aspect ratio of the video is not equal to one, this Cartesian index should be to the raw, unscaled, image frame.
    3. `NTuple{2}`: (x, y) where x and y are the horizontal and vertical pixel-distances between the left-top corner of the video-frame and the target at `start`. Note that regardless of the aspect ratio of the video, this coordinate should be to the scaled image frame (what you'd see in a video player).
    Defaults to `missing`.
- `window_size`: Defaults to a good minimal size that depends on the target width (see `guess_window_size` for details). But can be one of the following:
    1. `NTuple{2}`: a tuple (w, h) where w and h are the width and height of the window (region of interest) in which the algorithm will try to detect the target in the next frame. This should be larger than the `target_width` and relate to how fast the target moves between subsequent frames. 
    2. `Int`: both the width and height of the window (region of interest) in which the algorithm will try to detect the target in the next frame. This should be larger than the `target_width` and relate to how fast the target moves between subsequent frames. 
- `darker_target`: set to `true` if the target is darker than its background, and vice versa. Defaults to `true`.
- `fps`: frames per second. Sets how many times the target's location is registered per second. Set to a low number for faster and sparser tracking, but adjust the `window_size` accordingly. Defaults to an arbitrary value of 24 frames per second.
- `diagnostic_file`: specify a file path to save a diagnostic video showing a low-memory version of the tracking video with the path of the target superimposed on it. Defaults to nothing.

Returns a vector with the time-stamps per frame and a vector of Cartesian indices for the detection index per frame.
"""
function track(
        file::AbstractString;
        start::Real = 0,
        stop::Real = get_duration(file),
        target_width::Real = 25,
        start_location::Union{Missing, NTuple{2, Int}, CartesianIndex{2}} = missing,
        window_size::Union{Int, NTuple{2, Int}} = guess_window_size(target_width),
        darker_target::Bool = true,
        fps::Real = get_framerate(file),
        diagnostic_file::Union{Nothing, AbstractString} = nothing,
        apriltags::Int = 0,
        initial_search_factor::Real=4,
        white_point::Real = 1, # clamped linear rescaling
        calibration = nothing # calibration object
    )

    window_size = fix_window_size(window_size)
    # @show window_size
    return diagnose(diagnostic_file, darker_target, round(Int, (stop - start)*fps), calibration) do dia
        track_one(file, start, stop, target_width, start_location, window_size, darker_target, fps, dia, apriltags, initial_search_factor, white_point)
    end
end

# function track_one(file, start, stop, target_width, start_location, window_size, darker_target, ::Nothing, dia)
#     indices = [(1, 1)]
#
#     openvideo(file; target_format = AV_PIX_FMT_GRAY8) do vid
#         img = read(vid)
#         update_ratio!(dia, size(img))
#         seek(vid, start)
#         read!(vid, img) # and do something
#         trckr, indices[1] = get_start_ij_and_tracker(start_location, vid, img, target_width, window_size, darker_target)
#         while gettime(vid) < stop && !eof(vid)
#             read!(vid, trckr.img.data)
#             push!(indices, trckr(indices[end]))
#             dia(trckr.img.data, indices[end])
#         end
#     end
#     n = length(indices)
#     ts = range(start, stop, n)
#
#     return ts, CartesianIndex.(indices)
# end

function get_p(tags, n)
    RowCol.(reverse.(reshape(stack(getfield.(tags, :p)), 4n)))
end

function findHomography(src, dst, n)
    # mask = Matrix{Float64}(undef, 3, 3)
    h, mask = OpenCV.findHomography(OpenCV.Mat(reshape(reinterpret(Float32, src), 2, 4n, 1)), OpenCV.Mat(reshape(reinterpret(Float32, dst), 2, 4n, 1)))#, OpenCV.Mat(reshape(mask, 1, 3, 3)), 2000, 0.995)
    # h, mask = OpenCV.findHomography(OpenCV.Mat(reshape(reinterpret(Float32, src), 2, 1, 4n)), OpenCV.Mat(reshape(reinterpret(Float32, dst), 2, 1, 4n)), OpenCV.RANSAC, 5.0, OpenCV.Mat(reshape(mask, 1, 3, 3)), 2000, 0.995)
    SMatrix{3,3}(reshape(h, 3 ,3))'
end

push1 = Base.Fix2(push, 1)

function track_one(file, start, stop, target_width, start_location, window_size, darker_target, fps, dia, apriltags, initial_search_factor, white_point)
    # start and stop are taken as absolutes. To guarantee that, `ts` is set using `length` rather than the `step` key-word
    t = stop - start
    n = round(Int, fps * t) + 1
    ts = range(start, stop, n)
    indices = Vector{NTuple{2, Int}}(undef, n)
    xys = Vector{Union{Missing, RowCol}}(undef, n)

    bkgd = get_bkgd(file, start, stop)

    openvideo(file; target_format = AV_PIX_FMT_GRAY8) do vid
        vid_fps = framerate(vid)
        if isinf(vid_fps)
            vid_fps = get_framerate(file)
        end
        skip = round(Int, vid_fps / fps) - 1
        # img = Matrix{out_frame_eltype(vid)}(undef, out_frame_size(vid))
        img = read(vid)
        update_ratio!(dia, size(img))
        seek(vid, start)
        read!(vid, img) # and do something
        if !iszero(apriltags)
            detector = AprilTagDetector()
            tags = detector(collect(img))
            if length(tags) == apriltags
                dst = get_p(tags, apriltags)
                tag = tags[1]
                H = inv(SMatrix{3,3}(tag.H))
            else
                @error "less than $apriltags AprilTags were detected" length(tags)
            end
        end
        trckr, indices[1] = get_start_ij_and_tracker(start_location, vid, img, target_width, window_size, darker_target, initial_search_factor, white_point, bkgd)
        for i in 2:n
            skipframes(vid, skip, throwEOF = false)
            if eof(vid)
                ts = ts[1:i-1]
                deleteat!(indices, i:n)
                break
            end
            read!(vid, trckr.img.data)
            indices[i] = trckr(indices[i - 1])
            dia(trckr.img.data, indices[i])
            if !iszero(apriltags)
                tags = detector(collect(trckr.img.data))
                if length(tags) == apriltags
                    src = get_p(tags, apriltags)
                    h = findHomography(src, dst, apriltags)
                    trans = LinearMap(SDiagonal(96/2, 96/2)) ∘ pop ∘ LinearMap(H) ∘ LinearMap(h) ∘ push1 ∘ RowCol
                    xys[i] = trans(indices[i])
                end
            end
            # @show i
        end
    end
    return ts, CartesianIndex.(indices), xys

    # frame_index = openvideo(open(cmd), target_format = AV_PIX_FMT_GRAY8) do vid
    #     last_frame::Int = 1
    #     img = read(vid)
    #     update_ratio!(dia, size(img))
    #     trckr, indices[1] = get_start_ij_and_tracker(start_location, vid, img, target_width, window_size, darker_target)
    #     while !eof(vid) && last_frame < n
    #         last_frame += 1
    #         read!(vid, trckr.img.data)
    #         indices[last_frame] = trckr(indices[last_frame - 1])
    #         dia(trckr.img.data, indices[last_frame])
    #     end
    #     return last_frame
    # end
    # return ts[1:frame_index], CartesianIndex.(indices[1:frame_index])
end

"""
    track(files::AbstractVector; start::AbstractVector, stop::AbstractVector, target_width, start_location::AbstractVector, window_size, darker_target, fps, diagnostic_file)

Use a Difference of Gaussian (DoG) filter to track a target across multiple video `files`. `start`, `stop`, and `start_location` all must have the same number of elements as `files` does. If the second, third, etc elements in `start_location` are `missing` then the target is assumed to start where it ended in the previous video (as is the case in segmented videos).
"""
function track(
        files::AbstractVector;
        start::AbstractVector = zeros(length(files)),
        stop::AbstractVector = get_duration.(files),
        target_width::Real = 25,
        start_location::AbstractVector = similar(files, Missing),
        window_size::Union{Int, NTuple{2, Int}} = guess_window_size(target_width),
        darker_target::Bool = true,
        fps::Real = get_framerate(files[1]),
        diagnostic_file::Union{Nothing, AbstractString} = nothing,
        apriltags::Int = 0,
        initial_search_factor::Real = 4,
        white_point::Real = 1, # clamped linear rescaling
        calibration = nothing
    )

    @assert length(files) == length(start) == length(stop) == length(start_location) "Array length mismatch: files=$(length(files)), start=$(length(start)), stop=$(length(stop)), start_location=$(length(start_location))"

    nfiles = length(files)
    tss = Vector{StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}, Int64}}(undef, nfiles)
    ijs = Vector{Vector{CartesianIndex{2}}}(undef, nfiles)
    args = tuple.(files, start, stop, start_location)
    window_size = fix_window_size(window_size)

    diagnose(diagnostic_file, darker_target, round(Int, sum(stop .- start)*fps), calibration) do dia
        end_location = missing
        for (i, (f, t_start, t_stop, loc)) in enumerate(args)
            loc = coalesce(loc, end_location)
            tss[i], ijs[i] = track_one(f, t_start, t_stop, target_width, loc, window_size, darker_target, fps, dia, apriltags, initial_search_factor, white_point)
            end_location = ijs[i][end]
        end
    end
    n = sum(length, tss)
    ts = range(tss[1][1], step = step(tss[1]), length = n)
    ij = vcat(ijs...)

    return ts, ij
end

end
