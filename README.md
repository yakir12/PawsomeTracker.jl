# PawsomeTracker

[![Build Status](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/yakir12/PawsomeTracker.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/yakir12/PawsomeTracker.jl)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A simple, performant, and robust auto-tracker for videos of a single moving target. Uses a [Difference of Gaussian (DoG)](https://en.wikipedia.org/wiki/Difference_of_Gaussians) filter to track the target in the video file. Works with concurrency, videos that have a non-zero start-time, and pixel aspect ratios (i.e. SAR, DAR, etc) other than one.

## API

### Single video file

    track(file; start, stop, target_width, start_location, window_size)

Use a Difference of Gaussian (DoG) filter to track a target in a video `file`. 
- `start`: start tracking after `start` seconds. Defaults to 0.
- `stop`: stop tracking at `stop` seconds.  Defaults to 86399.999 seconds (24 hours minus one millisecond).
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
- `fps`: frames per second. Sets how many times the target's location is registered per second. Set to a low number for faster and sparser tracking, but adjust the `window_size` accordingly. Defaults to an arbitrary value of 24 frames per second.
- `diagnostic_file`: specify a file path to save a diagnostic video showing a low-memory version of the tracking video with the path of the target superimposed on it. Defaults to nothing.

Returns a vector with the time-stamps per frame and a vector of Cartesian indices for the detection index per frame.

### Multiple consecutive files (e.g. segmented video files)

    track(files::AbstractVector; start::AbstractVector, stop::AbstractVector, target_width, start_location::AbstractVector, window_size)

Use a Difference of Gaussian (DoG) filter to track a target across multiple video `files`. `start`, `stop`, and `start_location` all must have the same number of elemants as `files` does. If the second, third, etc elemants in `start_location` are `missing` then the target is assumed to start where it ended in the previous video (as is the case in segmented videos).


## Citing

See [`CITATION.bib`](CITATION.bib) for the relevant reference(s).
