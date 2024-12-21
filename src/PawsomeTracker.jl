module PawsomeTracker

# using LinearAlgebra
# using VideoIO, OffsetArrays, ImageFiltering, PaddedViews, StatsBase

using ImageFiltering: ImageFiltering, Kernel, imfilter
using LinearAlgebra: LinearAlgebra
using OffsetArrays: OffsetArrays
using PaddedViews: PaddedViews, PaddedView
using StatsBase: StatsBase, mode
using VideoIO: VideoIO, gettime, openvideo, out_frame_size, read, read!

export track

function getnext(guess, img, window, kernel, sz)
    frame = OffsetArrays.centered(img, guess)[window]
    x = imfilter(frame, kernel)
    _, i = findmax(x)
    guess = guess .+ Tuple(window[i])
    return min.(max.(guess, (1, 1)), sz)
end

function getwindow(window_size)
    radii = window_size .÷ 2
    wr = CartesianIndex(radii)
    window = -wr:wr
    return radii, window
end

function initiate(vid, _, start_index::CartesianIndex{2})
    sz = reverse(out_frame_size(vid))
    return sz, read(vid), Tuple(start_index)
end

function initiate(vid, _, start_xy::NTuple{2})
    sz = reverse(out_frame_size(vid))
    x, y = start_xy
    start_ij = round.(Int, (y, x / VideoIO.aspect_ratio(vid)))
    return sz, read(vid), start_ij
end

function initiate(vid, kernel, ::Missing)
    sz = reverse(out_frame_size(vid))
    guess = sz .÷ 2
    _, initial_window = getwindow(sz .÷ 2)
    img = read(vid)
    start_ij = getnext(guess, img, initial_window, kernel, sz)

    return sz, img, start_ij
end

function guess_window_size(target_width)
    h = round(Int, 1.5target_width)
    return (h, h)
end

"""
    track(file; start, stop, target_width, start_location, window_size)

Use a Difference of Gaussian (DoG) filter to track a target in a video `file`. 
- `start`: start tracking after `start` seconds. Defaults to 0.
- `stop`: stop tracking at `stop` seconds.  Defaults to the full duration of the video.
- `target_width`: the full width of the target (diameter, not radius). It is used as the FWHM of the center Gaussian in the DoG filter. Arbitrarily defaults to 25 pixels.
- `start_location`: one of three things:
    1. `missing`: the target will be detected in a large (half as large as the frame) window centered at the frame.
    2. `CartesianIndex{2}`: the cartesian index (into the image matrix) indicating where the target is at `start`. Note that when the aspect ratio of the video is not equal to one, this cartesian index should be to the raw, un-scaled, image frame.
    3. `NTuple{2}`: (x, y) where x and y are the horizontal and vertical pixel-distances between the left-top corner of the video-frame and the target at `start`. Note that regardless of the aspect ratio of the video, this coordinate should be to the scaled image frame (what you'd see in a video player).
    Defaults to `missing`.
- `window_size`: a tuple (w, h) where w and h are the width and height of the window (region of interest) in which the algorithm will in to detect the target in the next frame. This should be larger than the `target_width` and relate to how fast the target moves between subsequent frames. Defaults to 1.5 times the target width.

Returns a vector with the time-stamps per frame and a vector of cartesian indices for the detection index per frame.
"""
function track(file::AbstractString; 
        start::Real = 0,
        stop::Real = VideoIO.get_duration(file),
        target_width::Real = 25,
        start_location::Union{Missing, NTuple{2}, CartesianIndex{2}} = missing,
        window_size::NTuple{2, Int} = guess_window_size(target_width)
    )

    openvideo(vid -> _track(vid, start, stop, target_width, start_location, window_size), file, target_format=VideoIO.AV_PIX_FMT_GRAY8)
end

function _track(vid, start, stop, target_width, start_location, window_size)
    read(vid) # needed to get the right time offset t₀
    t₀ = gettime(vid)
    start += t₀
    stop += t₀
    seek(vid, start)

    σ = target_width/2.355
    kernel = -Kernel.DoG(σ)

    sz, img, start_ij = initiate(vid, kernel, start_location)

    indices = [start_ij]
    ts = [gettime(vid)]
    wr, window = getwindow(reverse(window_size))
    window_indices = UnitRange.(1 .- wr, sz .+ wr)
    fillvalue = mode(img)
    pimg = PaddedView(fillvalue, img, window_indices)

    while !eof(vid)
        read!(vid, pimg.data)
        guess = getnext(indices[end], pimg , window, kernel, sz)
        push!(indices, guess)
        push!(ts, gettime(vid))
        if ts[end] ≥ stop
            break
        end
    end

    # function index2xy(ij::CartesianIndex)
    #     i, j = Tuple(ij)
    #     return (j * VideoIO.aspect_ratio(vid), i)
    # end

    return ts .- t₀, CartesianIndex.(indices)
end

end
