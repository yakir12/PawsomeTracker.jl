# PawsomeTracker

[![Build Status](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/yakir12/PawsomeTracker.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/yakir12/PawsomeTracker.jl)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![Code Style: Runic](https://img.shields.io/badge/code%20style-Runic-violet)](https://github.com/fredrikekre/Runic.jl)

A simple, performant, and robust auto-tracker for videos of a single moving target. Uses a [Difference of Gaussian (DoG)](https://en.wikipedia.org/wiki/Difference_of_Gaussians) filter to track the target in the video file.

## Features

- **Fast and efficient**: Multi-threaded DoG filtering with pre-allocated buffers and view-based padding
- **Smart search**: Processes only local search windows instead of entire frames
- **Flexible input**: Auto-detects target location or accepts manual initialization
- **Segmented videos**: Seamlessly tracks across multiple consecutive video files
- **Aspect ratio aware**: Handles non-square pixel aspect ratios (SAR/DAR)
- **Time-based processing**: Works with videos that have non-zero start times
- **Diagnostic output**: Optional visualization showing tracking path overlaid on downscaled video
- **Configurable sampling**: Set custom fps independent of video framerate
- **Robust**: Comprehensive test suite with synthetic trajectories achieving <1 pixel RMSE accuracy

## Installation

```julia
using Pkg
Pkg.add("PawsomeTracker")
```

Or in the Julia REPL package mode (press `]`):
```
add PawsomeTracker
```

## Quick Start

```julia
using PawsomeTracker

# Track a dark target moving in a video
timestamps, positions = track(
    "my_video.mp4",
    target_width = 30,        # Target diameter in pixels
    start = 5.0,              # Start at 5 seconds
    stop = 60.0,              # End at 60 seconds
    darker_target = true      # Target is darker than background
)

# positions is a vector of CartesianIndex{2} indicating (row, col) in each frame
# timestamps is a vector of Float64 indicating time in seconds for each position
```

## How It Works

PawsomeTracker uses a **Difference of Gaussian (DoG)** filter to detect blob-like features in video frames. The algorithm:

1. **Initialization**:
   - Converts target width (FWHM) to Gaussian sigma using: `σ = target_width / (2√(2ln(2)))`
   - Creates a DoG kernel optimized for the target size
   - Determines initial target location (provided or auto-detected)

2. **Frame-by-Frame Tracking**:
   - Uses previous position as guess for next frame
   - Defines a search window centered on the guess
   - Applies DoG filter to the search window (multi-threaded)
   - Finds maximum response in filtered output → new target position
   - Clamps position to image bounds

3. **DoG Filter**:
   - Positive kernel for dark targets, negative for light targets
   - Convolves image with kernel; maximum response indicates target center
   - Effective for detecting blob-like objects with known size

### Core Architecture

The package is built around two main types:

- **`Tracker`**: The tracking engine that maintains the DoG kernel, padded image view, and pre-allocated buffers for efficient processing
- **`Diagnose`**: Optional diagnostic video generator that creates a downscaled (640×360) visualization with tracking path overlay

## API

### Single video file

```julia
track(file; start, stop, target_width, start_location, window_size, darker_target, fps, diagnostic_file)
```

Use a Difference of Gaussian (DoG) filter to track a target in a video `file`.

**Parameters:**

- `start`: Start tracking after `start` seconds. Defaults to `0`.
- `stop`: Stop tracking at `stop` seconds. Defaults to `86399.999` seconds (24 hours minus one millisecond).
- `target_width`: The full width of the target (diameter, not radius). Used as the FWHM of the center Gaussian in the DoG filter. Defaults to `25` pixels.
- `start_location`: One of the following:
    - `missing`: Target will be auto-detected in a large window (half frame size) centered on the frame.
    - `CartesianIndex{2}`: Cartesian index into the image matrix indicating target position at `start`. When aspect ratio ≠ 1, this should reference the raw, unscaled image frame.
    - `NTuple{2}`: `(x, y)` where x and y are horizontal and vertical pixel distances from the top-left corner to the target at `start`. This coordinate should reference the scaled image frame (as seen in a video player), regardless of aspect ratio.
    - Defaults to `missing`.
- `window_size`: Search window size. Defaults to an optimal size based on target width (see `guess_window_size`). Can be:
    - `NTuple{2}`: `(w, h)` where w and h are width and height of the search window in pixels. Should be larger than `target_width` and relate to how fast the target moves between frames.
    - `Int`: Both width and height of the square search window.
- `darker_target`: Set to `true` if the target is darker than its background, `false` otherwise. Defaults to `true`.
- `fps`: Frames per second for sampling. Sets how often the target location is registered. Use lower values for faster, sparser tracking (adjust `window_size` accordingly). Defaults to `24` fps.
- `diagnostic_file`: File path to save a diagnostic video showing the tracking path superimposed on a low-resolution version of the video. Defaults to `nothing`.

**Returns:**
- `timestamps`: Vector of time stamps (in seconds) for each tracked frame
- `positions`: Vector of `CartesianIndex{2}` indicating detected target position per frame

### Multiple consecutive files (e.g. segmented video files)

```julia
track(files::AbstractVector; start::AbstractVector, stop::AbstractVector,
      target_width, start_location::AbstractVector, window_size,
      darker_target, fps, diagnostic_file)
```

Use a Difference of Gaussian (DoG) filter to track a target across multiple video `files`.

**Requirements:**
- `start`, `stop`, and `start_location` must all have the same number of elements as `files`
- If elements 2, 3, etc. in `start_location` are `missing`, the target is assumed to start where it ended in the previous video (typical for segmented videos)

**Returns:** Concatenated timestamps and positions across all videos.

## Examples

### Basic tracking with auto-detection

```julia
using PawsomeTracker

# Let the algorithm auto-detect the target
times, coords = track("video.mp4", target_width=35)
```

### Tracking with manual start position

```julia
# Provide starting coordinates as (x, y) from top-left
times, coords = track(
    "video.mp4",
    target_width = 25,
    start_location = (320, 240),
    darker_target = false  # Light target on dark background
)
```

### Tracking with diagnostic output

```julia
# Generate a diagnostic video to verify tracking quality
times, coords = track(
    "video.mp4",
    target_width = 30,
    window_size = 100,
    fps = 30,
    diagnostic_file = "tracking_diagnostic.mp4"
)
```

### Tracking segmented videos

```julia
# Track across multiple video segments
files = ["segment1.mp4", "segment2.mp4", "segment3.mp4"]
starts = [0.0, 0.0, 0.0]
stops = [Inf, Inf, Inf]  # Process entire videos
locations = [missing, missing, missing]  # Auto-continue between segments

times, coords = track(
    files,
    start = starts,
    stop = stops,
    target_width = 28,
    start_location = locations
)
```

### Processing results

```julia
times, coords = track("video.mp4", target_width=30)

# Extract x, y coordinates
x_coords = [c[2] for c in coords]  # Column (x)
y_coords = [c[1] for c in coords]  # Row (y)

# Calculate distances traveled
using LinearAlgebra
distances = [norm([x_coords[i]-x_coords[i-1], y_coords[i]-y_coords[i-1]])
             for i in 2:length(coords)]
total_distance = sum(distances)
```

## Performance Considerations

- **Window size**: Larger windows increase accuracy but reduce speed. Keep it just large enough to accommodate frame-to-frame movement.
- **FPS**: Lower sampling rates process fewer frames. Adjust `window_size` proportionally when reducing fps.
- **Threading**: DoG filtering is multi-threaded. Performance scales with available CPU cores.
- **Diagnostic videos**: Creating diagnostic output adds overhead. Disable for production runs.

## Testing

PawsomeTracker includes a comprehensive test suite that:
- Generates synthetic videos with known spiral trajectories
- Tests various configurations (fps, aspect ratios, target brightness, start locations)
- Verifies segmented video handling
- Validates thread safety
- Achieves sub-pixel accuracy (RMSE < 1 pixel)
- Includes code quality checks with Aqua.jl

Run tests with:
```julia
using Pkg
Pkg.test("PawsomeTracker")
```

## Citing

See [`CITATION.bib`](CITATION.bib) for the relevant reference(s).
