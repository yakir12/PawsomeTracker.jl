module PawsomeTracker

# using LinearAlgebra
# using VideoIO, OffsetArrays, ImageFiltering, PaddedViews, StatsBase

using ImageFiltering: ImageFiltering, Kernel, imfilter!, Algorithm, NoPad
using LinearAlgebra: LinearAlgebra
using OffsetArrays: centered, OffsetMatrix
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
using ComputationalResources: CPUThreads

const FACE = Ref{FTFont}()

function __init__()
    assets = @path joinpath(@__DIR__, "../assets")
    FACE[] = FTFont(joinpath(assets, "TeXGyreHerosMakie-Regular.otf"))
end

export track

const BW = Matrix{Gray{N0f8}}

include("ffmpeg.jl")
include("diagnose.jl")

struct Tracker
    sz::Tuple{Int64, Int64}
    radii::Tuple{Int64, Int64}
    kernel::OffsetMatrix{Float64, Matrix{Float64}}
    img::PaddedView{Gray{N0f8},2,Tuple{Base.IdentityUnitRange{UnitRange{Int64}},Base.IdentityUnitRange{UnitRange{Int64}}},PermutedDimsArray{Gray{N0f8}, 2, (2, 1), (2, 1), Matrix{Gray{N0f8}}}}
    buff::OffsetMatrix{Float64, Matrix{Float64}}

    function Tracker(_img, target_width, window_size, darker_target)
        sz = size(_img)
        σ = target_width/2sqrt(2log(2))
        direction = darker_target ? -1 : +1
        kernel = direction*Kernel.DoG(σ)
        radii = window_size .÷ 2
        h = radii .+ size(kernel)
        pad_indices = UnitRange.(1 .- h, sz .+ h)
        fillvalue = mode(_img)
        img = PaddedView(fillvalue, _img, pad_indices)
        _buff = Matrix{Float64}(undef, length.(pad_indices)) 
        buff = OffsetMatrix(_buff, pad_indices)
        return new(sz, radii, kernel, img, buff)
    end
end

function (trckr::Tracker)(guess::NTuple{2, Int})
    window_indices = UnitRange.(guess .- trckr.radii, guess .+ trckr.radii)
    imfilter!(CPUThreads(Algorithm.FIR()), trckr.buff, trckr.img, trckr.kernel, NoPad(), window_indices)
    # # imfilter!(CPU1(Algorithm.FIR()), trckr.buff, trckr.img, trckr.kernel, NoPad(), window_indices)
    v = view(trckr.buff, window_indices...)
    _, ij = findmax(v)
    guess = getindex.(parentindices(v), Tuple(ij))
    return min.(max.(guess, (1, 1)), trckr.sz)
end

function guess_window_size(target_width)
    σ = target_width/2sqrt(log(2))
    l = 4ceil(Int, σ) + 1 # calculates the size of the DoG kernel
    return l
end

fix_window_size(wh::NTuple{2, Int}) = reverse(wh)

fix_window_size(l::Int) = (l, l)

function get_start_ij(start_index::CartesianIndex{2}, _, _, _, _)
    return Tuple(start_index)
end

function get_start_ij(start_xy::NTuple{2, Int}, vid, _, _, _)
    sar = aspect_ratio(vid)
    x, y = start_xy
    return round.(Int, (y, x / sar))
end

function get_start_ij(::Missing, _, target_width, darker_target, img)
    sz = size(img)
    window_size = sz .÷ 4 # this greatly affects processing time!
    trckr = Tracker(img, target_width, window_size, darker_target) # 0.5 seconds
    return trckr(trckr.sz .÷ 2)
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
        start_location::Union{Missing, NTuple{2, Int}, CartesianIndex{2}} = missing,
        window_size::Union{Int, NTuple{2, Int}} = guess_window_size(target_width),
        darker_target::Bool = true,
        fps::Real = get_fps(file),
        diagnostic_file::Union{Nothing, AbstractString} = nothing
    )

    window_size = fix_window_size(window_size)
    diagnose(diagnostic_file, darker_target) do dia
        track_one(file, start, stop, target_width, start_location, window_size, darker_target, fps, dia)
    end
end

function track_one(file, start, stop, target_width, start_location, window_size, darker_target, fps, dia)
    ts = range(start, stop; step = 1/fps)
    n = length(ts)
    indices = Vector{NTuple{2, Int}}(undef, n)

    t = stop - start
    cmd = `$(ffmpeg()) -loglevel 8 -ss $start -i $file -t $t -r $fps -preset veryfast -f matroska -`

    frame_index = openvideo(open(cmd), target_format=AV_PIX_FMT_GRAY8) do vid
        last_frame::Int = 1
        img = read(vid)
        indices[1] = get_start_ij(start_location, vid, target_width, darker_target, img)
        trckr = Tracker(img, target_width, window_size, darker_target)
        while !eof(vid) && last_frame < n
            last_frame += 1
            read!(vid, trckr.img.data)
            indices[last_frame] = trckr(indices[last_frame - 1])
            dia(trckr.img.data, indices[last_frame])
        end
        return last_frame
    end
    return ts[1:frame_index], CartesianIndex.(indices[1:frame_index])
end

function track(files::AbstractVector; 
        start::Union{Real, AbstractVector} = 0,
        stop::Union{Real, AbstractVector} = get_duration.(files),
        target_width::Real = 25,
        start_location::AbstractVector = similar(files, Missing),
        window_size::Union{Int, NTuple{2, Int}} = guess_window_size(target_width),
        darker_target::Bool = true,
        fps::Real = get_fps(files[1]),
        diagnostic_file::Union{Nothing, AbstractString} = nothing
    )

    nfiles = length(files)
    tss = Vector{StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}, Int64}}(undef, nfiles)
    ijs = Vector{Vector{CartesianIndex{2}}}(undef, nfiles)
    args = tuple.(files, start, stop, start_location)
    window_size = fix_window_size(window_size)

    diagnose(diagnostic_file, darker_target) do dia
        end_location = missing
        for (i, (file, start, stop, start_location)) in enumerate(args)
            start_location = coalesce(start_location, end_location)
            tss[i], ijs[i] = track_one(file, start, stop, target_width, start_location, window_size, darker_target, fps, dia)
            end_location = ijs[i][end]
        end
    end
    n = sum(length, tss)
    ts = range(tss[1][1], step = step(tss[1]), length = n)
    ij = vcat(ijs...)

    return ts, ij
end


# TODO: if I'm resizeing evrything, might as well track the smaller image, 



# function index2xy(ij::CartesianIndex)
#     i, j = Tuple(ij)
#     return (j * VideoIO.aspect_ratio(vid), i)
# end

end
