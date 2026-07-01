# Constants for diagnostic video generation
const DIAGNOSTIC_VIDEO_SIZE = (360, 640)
const TRACE_BUFFER_SIZE = 100

abstract type Diagnosis end

struct Diagnose <: Diagnosis
    label::String
    buffer::Matrix{Gray{N0f8}}
    color::Gray{N0f8}
    writer::VideoWriter
    trace::CircularBuffer{CartesianIndex{2}}
    ratio::Ref{NTuple{2, Float64}}
    state::Ref{Int}
    fps::Int

    function Diagnose(file, darker_target, nframes)
        label = first(splitext(basename(file)))
        buff_sz = DIAGNOSTIC_VIDEO_SIZE
        buffer = Matrix{Gray{N0f8}}(undef, buff_sz...)
        color = darker_target ? Gray{N0f8}(1) : Gray{N0f8}(0)
        writer = open_video_out(file, buffer)
        trace = CircularBuffer{CartesianIndex{2}}(TRACE_BUFFER_SIZE)
        ratio = Ref{NTuple{2, Float64}}()
        fps = nframes < 100 ? 1 : round(Int, nframes/100)
        return new(label, buffer, color, writer, trace, ratio, Ref(0), fps)
    end
end
diagnose(file::AbstractString, darker_target::Bool, nframes::Int, ::Nothing) = Diagnose(file, darker_target, nframes)

function update_ratio!(dia::Diagnose, sz)
    return dia.ratio[] = size(dia.buffer) ./ sz
end

function (dia::Diagnose)(img, point)
    dia.state[] += 1
    if rem(dia.state[], dia.fps) == 0
        ij = CartesianIndex(round.(Int, point .* dia.ratio[]))
        push!(dia.trace, ij)
        imresize!(dia.buffer, img)
        renderstring!(dia.buffer, dia.label, FACE[], 20, 20, 20, halign = :hleft, valign = :vtop)
        draw!(dia.buffer, CirclePointRadius(ij, 7; thickness = 3, fill = false), dia.color)
        draw!(dia.buffer, Path(dia.trace), dia.color)
        write(dia.writer, dia.buffer)
    end
    return nothing
end

Base.close(dia :: Diagnosis) = close_video_out!(dia.writer)

struct Dont end
diagnose(::Nothing, _, _, _) = Dont()
(::Dont)(_, _) = nothing
Base.close(::Dont) = nothing
update_ratio!(::Dont, _) = nothing

function diagnose(f, file, darker_target, nframes, calibration)
    dia = diagnose(file, darker_target, nframes, calibration)
    return try
        f(dia)
    finally
        close(dia)
    end
end

struct DiagnoseCalib <: Diagnosis
    label::String
    # buffer::OffsetMatrix{Gray{N0f8}, Matrix{Gray{N0f8}}}
    indices
    color::Gray{N0f8}
    writer::VideoWriter
    trace::CircularBuffer{CartesianIndex{2}}
    state::Ref{Int}
    fps::Int
    image2real
    real2image
    radius::Int
    font::Int

    function DiagnoseCalib(file, darker_target, nframes, calib)
        label = first(splitext(basename(file)))
        ratio = 2
        D = LinearMap(SDiagonal{2}(ratio*calib.ratio*I))
        real2image = calib.real2image ∘ D
        image2real = inv(D) ∘ calib.image2real
        m = min(calib.width, calib.height) ÷ ratio
        indices = (-m÷2:m÷2 - 1, -m÷2:m÷2 - 1)
        buffer = OffsetMatrix(Matrix{Gray{N0f8}}(undef, m, m), indices...)
        color = darker_target ? Gray{N0f8}(1) : Gray{N0f8}(0)
        writer = open_video_out(file, parent(buffer))
        trace = CircularBuffer{CartesianIndex{2}}(TRACE_BUFFER_SIZE)
        fps = nframes < 100 ? 1 : round(Int, nframes/100)
        return new(label, indices, color, writer, trace, Ref(0), fps, image2real, real2image, m ÷ 30, m ÷ 16)
    end
end
diagnose(file::AbstractString, darker_target::Bool, nframes::Int, calibration) = DiagnoseCalib(file, darker_target, nframes, calibration)

function (dia::DiagnoseCalib)(img, point)
    dia.state[] += 1
    if rem(dia.state[], dia.fps) == 0
        ij = CartesianIndex(Tuple(round.(Int, dia.image2real(point))))
        push!(dia.trace, ij)
        wimg = warp(img, dia.real2image, dia.indices)
        draw!(wimg, CirclePointRadius(ij, dia.radius; thickness = dia.radius ÷ 2, fill = false), dia.color)
        draw!(wimg, Path(dia.trace), dia.color)
        wimg = parent(wimg)
        renderstring!(wimg, dia.label, FACE[], dia.font, dia.font, dia.font, halign = :hleft, valign = :vtop)
        write(dia.writer, wimg)
    end
    return nothing
end

update_ratio!(::DiagnoseCalib, _) = nothing
