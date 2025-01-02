# PawsomeTracker

[![Build Status](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/yakir12/PawsomeTracker.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/yakir12/PawsomeTracker.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/yakir12/PawsomeTracker.jl)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A simple, performant, and robust auto-tracker for videos of a single moving target. Uses a [Difference of Gaussian (DoG)](https://en.wikipedia.org/wiki/Difference_of_Gaussians) filter to track the target in the video file. Works with concurrency, videos that have a non-zero start-time, and pixel aspect ratios (i.e. SAR, DAR, etc) other than one.

## Citing

See [`CITATION.bib`](CITATION.bib) for the relevant reference(s).
