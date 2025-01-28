module PawsomeTracker

# using LinearAlgebra
# using VideoIO, OffsetArrays, ImageFiltering, PaddedViews, StatsBase

using ImageFiltering: ImageFiltering, Kernel, imfilter
using LinearAlgebra: LinearAlgebra
using OffsetArrays: OffsetArrays
using PaddedViews: PaddedViews, PaddedView
using StatsBase: StatsBase, mode
using FFMPEG_jll: ffmpeg, ffprobe
using VideoIO: openvideo, AV_PIX_FMT_GRAY8, aspect_ratio, open_video_out, VideoWriter, close_video_out!, out_frame_size
using ImageDraw: draw!, CirclePointRadius
using FreeTypeAbstraction: renderstring!, findfont, FTFont
using ColorTypes: Gray
using FixedPointNumbers: N0f8
using ImageTransformations: imresize!
using RelocatableFolders: @path

const ASSETS = @path joinpath(@__DIR__, "../assets")

export track

include("ffmpeg.jl")
include("diagnose.jl")

function getnext(guess, img, window, kernel, sz)
    frame = OffsetArrays.centered(img, guess)[window]
    x = imfilter(frame, kernel)
    _, i = findmax(x)
    guess = guess .+ Tuple(window[i])
    return min.(max.(guess, (1, 1)), sz)
end

function guess_window_size(target_width)
    σ = target_width/2sqrt(log(2))
    l = 4ceil(Int, σ) + 1 # calculates the size of the DoG kernel
    return (l, l)
end

fix_window_size(wh::NTuple{2, Int}) = reverse(wh)

fix_window_size(l::Int) = (l, l)

function getwindow(window_size)
    radii = window_size .÷ 2
    wr = CartesianIndex(radii)
    window = -wr:wr
    return radii, window
end

function initiate(start_index::CartesianIndex{2}, _, _, _, _)
    return Tuple(start_index)
end

function initiate(start_xy::NTuple{2}, vid, _, _, _)
    x, y = start_xy
    sar = aspect_ratio(vid)
    start_ij = round.(Int, (y, x / sar))
    return start_ij
end

function initiate(::Missing, _, img, sz, kernel)
    guess = sz .÷ 2
    _, initial_window = getwindow(sz .÷ 5)
    start_ij = getnext(guess, img, initial_window, kernel, sz)
    return start_ij
end

"""
    track(file; start, stop, target_width, start_location, window_size)

Use a Difference of Gaussian (DoG) filter to track a target in a video `file`. 
- `start`: start tracking after `start` seconds. Defaults to 0.
- `stop`: stop tracking at `stop` seconds.  Defaults to the full duration of the video.
- `target_width`: the full width of the target (diameter, not radius). It is used as the FWHM of the center Gaussian in the DoG filter. Arbitrarily defaults to 25 pixels.
- `start_location`: one of the following:
    1. `missing`: the target will be detected in a large (half as large as the frame) window centered at the frame.
    2. `CartesianIndex{2}`: the Cartesian index (into the image matrix) indicating where the target is at `start`. Note that when the aspect ratio of the video is not equal to one, this Cartesian index should be to the raw, unscaled, image frame.
    3. `NTuple{2}`: (x, y) where x and y are the horizontal and vertical pixel-distances between the left-top corner of the video-frame and the target at `start`. Note that regardless of the aspect ratio of the video, this coordinate should be to the scaled image frame (what you'd see in a video player).
    Defaults to `missing`.
- `window_size`: Defaults to to a good minimal size that depends on the target width (see `fix_window_size` for details). But can be one of the following:
    1. `NTuple{2}`: a tuple (w, h) where w and h are the width and height of the window (region of interest) in which the algorithm will try to detect the target in the next frame. This should be larger than the `target_width` and relate to how fast the target moves between subsequent frames. 
    2. `Int`: both the width and height of the window (region of interest) in which the algorithm will try to detect the target in the next frame. This should be larger than the `target_width` and relate to how fast the target moves between subsequent frames. 
- `darker_target`: set to `true` if the target is darker than its background, and vice versa. Defaults to `true`.
- `fps`: frames per second. Sets how many times the target's location is registered per second. Set to a low number for faster and sparser tracking, but adjust the `window_size` accordingly. Defaults to the actual frame rate of the video.

Returns a vector with the time-stamps per frame and a vector of Cartesian indices for the detection index per frame.
"""
function track(file::AbstractString; 
        start::Real = 0,
        stop::Real = get_duration(file),
        target_width::Real = 25,
        start_location::Union{Missing, NTuple{2}, CartesianIndex{2}} = missing,
        window_size::Union{Int, NTuple{2, Int}} = guess_window_size(target_width),
        darker_target::Bool = true,
        fps::Real = get_fps(file),
        diagnostic_file::Union{Nothing, AbstractString} = nothing
    )

    ts = range(start, stop - 0.001; step = 1/fps)

    σ = target_width/2sqrt(2log(2))
    kernel = darker_target ? -Kernel.DoG(σ) : Kernel.DoG(σ)

    n = length(ts)
    indices = Vector{NTuple{2, Int}}(undef, n)
    wr, window = getwindow(fix_window_size(window_size))

    t = stop - start
    cmd = `$(ffmpeg()) -loglevel 8 -ss $start -i $file -t $t -r $fps -preset veryfast -f matroska -`

    openvideo(open(cmd), target_format=AV_PIX_FMT_GRAY8) do vid
        img = read(vid)
        sz = size(img)
        start_ij = initiate(start_location, vid, img, sz, kernel)

        indices[1] = start_ij

        window_indices = UnitRange.(1 .- wr, sz .+ wr)
        fillvalue = mode(img)
        pimg = PaddedView(fillvalue, img, window_indices)

        diagnose(diagnostic_file, sz, darker_target) do dia
            for i in 2:n
                read!(vid, pimg.data)
                indices[i] = getnext(indices[i - 1], pimg , window, kernel, sz)
                dia(pimg.data, indices[i])
            end
        end
    end

    return ts, CartesianIndex.(indices)
end

function _track(file, start, stop, target_width, start_location, window_size, darker_target, fps, dia)
    ts = range(start, stop - 0.001; step = 1/fps)

    σ = target_width/2sqrt(2log(2))
    kernel = darker_target ? -Kernel.DoG(σ) : Kernel.DoG(σ)

    n = length(ts)
    indices = Vector{NTuple{2, Int}}(undef, n)
    wr, window = getwindow(fix_window_size(window_size))

    t = stop - start
    cmd = `$(ffmpeg()) -loglevel 8 -ss $start -i $file -t $t -r $fps -preset veryfast -f matroska -`

    openvideo(open(cmd), target_format=AV_PIX_FMT_GRAY8) do vid
        img = read(vid)
        sz = size(img)
        start_ij = initiate(start_location, vid, img, sz, kernel)

        indices[1] = start_ij

        window_indices = UnitRange.(1 .- wr, sz .+ wr)
        fillvalue = mode(img)
        pimg = PaddedView(fillvalue, img, window_indices)

        for i in 2:n
            read!(vid, pimg.data)
            indices[i] = getnext(indices[i - 1], pimg , window, kernel, sz)
            dia(pimg.data, indices[i])
        end
    end

    return ts, CartesianIndex.(indices)
end

function track(files::AbstractVector; 
        start::Union{Real, AbstractVector} = 0,
        stop::Union{Real, AbstractVector} = get_duration.(files),
        target_width::Real = 25,
        start_location::Vector = similar(files, Missing),
        window_size::Union{Int, NTuple{2, Int}} = guess_window_size(target_width),
        darker_target::Bool = true,
        fps::Real = get_fps(files[1]),
        diagnostic_file::Union{Nothing, AbstractString} = nothing
    )

    nfiles = length(files)
    tss = Vector{StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}, Int64}}(undef, nfiles)
    ijs = Vector{Vector{CartesianIndex{2}}}(undef, nfiles)

    args = tuple.(files, start, stop, start_location)

    file1, start1, stop1, start_location1 = args[1]
    t = stop1 - start1
    cmd = `$(ffmpeg()) -loglevel 8 -ss $start1 -i $file1 -t $t -r $fps -preset veryfast -f matroska -`
    sz = reverse(openvideo(out_frame_size, open(cmd), target_format=AV_PIX_FMT_GRAY8))
    diagnose(diagnostic_file, sz, darker_target) do dia
        end_location = missing
        for (i, (file, start, stop, start_location)) in enumerate(args)
            start_location = coalesce(start_location, end_location)
            ts, ij = _track(file, start, stop, target_width, start_location, window_size, darker_target, fps, dia)
            tss[i] = ts
            ijs[i] = ij
            end_location = ij[end]
        end
    end
    n = sum(length, tss)
    ts = range(tss[1][1], step = step(tss[1]), length = n)
    ij = vcat(ijs...)

    return ts, ij
end




# function _track(vid, n, target_width, start_location, window_size, darker_target, diagnostic_file, dia)
#     σ = target_width/2sqrt(2log(2))
#     kernel = darker_target ? -Kernel.DoG(σ) : Kernel.DoG(σ)
#
#     img = read(vid)
#     sz = size(img)
#     start_ij = initiate(start_location, vid, img, sz, kernel)
#
#     indices = Vector{NTuple{2, Int}}(undef, n)
#     indices[1] = start_ij
#
#     wr, window = getwindow(window_size)
#     window_indices = UnitRange.(1 .- wr, sz .+ wr)
#     fillvalue = mode(img)
#     pimg = PaddedView(fillvalue, img, window_indices)
#
#     for i in 2:n
#         read!(vid, pimg.data)
#         indices[i] = getnext(indices[i - 1], pimg , window, kernel, sz)
#         dia(pimg.data, indices[i])
#     end
#
#     return indices
# end
#
# function track(files::Vector{AbstractString};
#         start = 0,
#         stop = get_duration.(files),
#         target_width = 25,
#         start_location = missing,
#         window_size = guess_window_size(target_width),
#         darker_target = true,
#         fps = get_fps.(files),
#         diagnostic_file = nothing)
#
#     ts = range(start, stop; step = 1/fps)
#     n = length(ts)
#     t = stop - start
#     cmd = `$(ffmpeg()) -loglevel 8 -ss $start -i $file -t $t -r $fps -preset veryfast -f matroska -`
#     ij = diagnose(diagnostic_file, img) do dia
#         openvideo(vid -> _track(vid, n, target_width, start_location, fix_window_size(window_size), darker_target, diagnostic_file, dia), open(cmd), target_format=AV_PIX_FMT_GRAY8)
#     end
#
#     tss, ijs = diagnose(diagnostic_file, img) do dia
#         track2.(files, start, stop, target_width, start_location, window_size, darker_target, fps)
#     end
# end
#
# function track2(file, start, stop, target_width, start_location, window_size, darker_target, fps)
#     ts = range(start, stop; step = 1/fps)
#     n = length(ts)
#     t = stop - start
#     cmd = `$(ffmpeg()) -loglevel 8 -ss $start -i $file -t $t -r $fps -preset veryfast -f matroska -`
#     ij = openvideo(vid -> _track(vid, n, target_width, start_location, fix_window_size(window_size), darker_target, diagnostic_file), open(cmd), target_format=AV_PIX_FMT_GRAY8)
#     return ts, CartesianIndex.(ij)
# end


# TODO: if I'm resizeing evrything, might as well track the smaller image, 



# function index2xy(ij::CartesianIndex)
#     i, j = Tuple(ij)
#     return (j * VideoIO.aspect_ratio(vid), i)
# end


end
