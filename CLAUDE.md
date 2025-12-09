# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PawsomeTracker.jl is a Julia package for tracking a single moving target in video files using a Difference of Gaussian (DoG) filter. It's designed to be fast, robust, and handle real-world video complexities like non-square pixel aspect ratios, segmented video files, and non-zero start times.

## Development Commands

### Running Tests

```bash
# Run all tests with single thread
julia --threads=1 --project=. -e 'using Pkg; Pkg.test()'

# Run tests with multiple threads (required for threaded test)
julia --threads=4 --project=. -e 'using Pkg; Pkg.test()'
```

### Test Environment

Tests require FFmpeg for video creation. The test suite:
- Generates synthetic videos with known spiral trajectories
- Tests tracking accuracy (target: RMSE < 1 pixel)
- Validates multiple configurations (fps, aspect ratios, target brightness, etc.)
- Tests segmented video handling and thread safety

### Package Management

```bash
# Activate the project environment
julia --project=.

# In Julia REPL, instantiate dependencies
using Pkg
Pkg.instantiate()

# Add new dependencies
Pkg.add("PackageName")
```

## Architecture

### Core Types

**`Tracker`** (src/PawsomeTracker.jl:29-60)
The main tracking engine. Key responsibilities:
- Maintains the DoG kernel computed from target width
- Manages a padded view of the image for boundary handling
- Pre-allocates buffers for efficient frame-to-frame processing
- Processes local search windows (not entire frames) for performance
- Multi-threaded DoG filtering via `CPUThreads()`

When called as a functor with a guess position `(row, col)`, it:
1. Defines a search window around the guess
2. Applies DoG filter to that window
3. Finds maximum response → new target position
4. Clamps result to image bounds

**`Diagnose`** (src/diagnose.jl:1-51)
Optional diagnostic video generator. Features:
- Downscales video to 640×360 for memory efficiency
- Overlays tracking path on video frames
- Maintains circular buffer of last 100 positions
- Uses `Dont` struct pattern for no-op when diagnostics disabled

### Key Design Patterns

**Padded Views**: The `Tracker` uses `PaddedViews.jl` to handle image boundaries elegantly. Padding is computed based on kernel size + search window radius, filled with the mode (most common) pixel value from the image.

**Window-based Processing**: Instead of filtering entire frames, only processes a search window around the previous position. Window size defaults to `4*ceil(Int, σ) + 1` where `σ` is computed from target width's FWHM.

**Coordinate Systems**: Carefully handles two coordinate systems:
- `CartesianIndex{2}`: (row, col) into raw image matrix
- `NTuple{2}`: (x, y) pixel coordinates accounting for aspect ratio

The `get_guess()` functions (lines 72-88) convert between these systems using the video's aspect ratio.

**Auto-detection**: When `start_location=missing`, uses a large search window (1/4 frame size) on the first frame, then switches to the normal window size for efficiency.

**Segmented Videos**: The multi-file `track()` method handles video segments by:
- Processing each file sequentially
- Using `coalesce(start_location, end_location)` to continue from previous segment
- Concatenating timestamps with proper step alignment

### FFmpeg Integration

Uses FFmpeg via pipes for video reading:
```julia
cmd = `$(ffmpeg()) -loglevel 8 -ss $start -i $file -t $t -vf fps=$fps -preset veryfast -f matroska -`
```

This approach:
- Seeks to start time before decoding (`-ss $start`)
- Resamples to target fps
- Outputs grayscale frames via matroska pipe
- Read via `VideoIO.openvideo()` with `AV_PIX_FMT_GRAY8`

## Important Implementation Details

### DoG Filter Calculation

Target width → Gaussian sigma: `σ = target_width / (2√(2ln(2)))`

This treats `target_width` as the Full Width at Half Maximum (FWHM) of the center Gaussian.

### Aspect Ratio Handling

Videos with non-square pixels (SAR ≠ 1) require coordinate transformation:
- Raw frames have unscaled dimensions
- Displayed frames account for aspect ratio
- The code handles both coordinate systems throughout

### Multi-threading

DoG filtering uses `CPUThreads()` from ComputationalResources.jl. Tests verify thread safety by running tracking on multiple threads concurrently.

### Return Values

Both `track()` methods return:
- `timestamps`: Vector of time stamps (Float64) in seconds
- `positions`: Vector of CartesianIndex{2} indicating (row, col) in raw image frame

Note: Positions are CartesianIndex (row, col), not (x, y) pixel coordinates.
