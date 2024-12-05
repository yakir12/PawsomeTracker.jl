# PawsomeTracker

[![Build Status](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml?query=branch%3Amain)

Use a Difference of Gaussian (DoG) filter to track a target in a video file.

## Usage

    track(file; start, stop, target_width, start_xy, window_size)

- `file`: the full path to the video file.
- `start`: start tracking after `start` seconds. Defaults to 0.
- `stop`: stop tracking at `stop` seconds.  Defaults to the full duration of the video.
- `target_width`: the full width of the target (diameter, not radius). It is used as the FWHM of the center Gaussian in the DoG filter. Arbitrarily defaults to 25 pixels.
- `start_xy`: a tuple (x, y) where x and y are the horizontal and vertical pixel-distances between the left-top corner of the video-frame and the center of the target at `start`. If `start_xy` is `missing`, the target will be detected in a large (half as large as the frame) window centered at the frame. Defaults to `missing`.
- `window_size`: a tuple (w, h) where w and h are the width and height of the window (region of interest) in which the algorithm will in to detect the target in the next frame. This should be larger than the `target_width` and relate to how fast the target moves between subsequent frames. Defaults to 1.5 times the target width.

Returns a vector with the time-stamps per frame, and a vector of (x, y) tuples for the detection per frame.
