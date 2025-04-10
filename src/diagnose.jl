struct Diagnose
    label::String
    buffer::Matrix{Gray{N0f8}}
    color::Gray{N0f8}
    writer::VideoWriter
    trace::CircularBuffer{CartesianIndex{2}}
    ratio::Ref{NTuple{2, Float64}}

    function Diagnose(file, darker_target)
        label = first(splitext(basename(file)))
        buff_sz = (360, 640)
        buffer = Matrix{Gray{N0f8}}(undef, buff_sz...)
        color = darker_target ? Gray{N0f8}(1) : Gray{N0f8}(0)
        writer = open_video_out(file, buffer)
        trace = CircularBuffer{CartesianIndex{2}}(100)
        ratio = Ref{NTuple{2, Float64}}()
        new(label, buffer, color, writer, trace, ratio)
    end
end
diagnose(file::AbstractString, darker_target::Bool) = Diagnose(file, darker_target)

function update_ratio!(dia::Diagnose, sz)
    dia.ratio[] = size(dia.buffer) ./ sz
end

function (dia::Diagnose)(img, point)
    ij = CartesianIndex(round.(Int, point .* dia.ratio[]))
    push!(dia.trace, ij)
    imresize!(dia.buffer, img)
    renderstring!(dia.buffer, dia.label, FACE[], 10, 10, 10, halign=:hleft, valign = :vtop)
    draw!(dia.buffer, CirclePointRadius(ij, 2), dia.color)
    draw!(dia.buffer, Path(dia.trace), dia.color)
    write(dia.writer, dia.buffer)
end

Base.close(dia::Diagnose) = close_video_out!(dia.writer)

struct Dont end
diagnose(::Nothing, _) = Dont()
(::Dont)(_, _) = nothing
Base.close(::Dont) = nothing
update_ratio!(::Dont, _) = nothing

function diagnose(f, file, darker_target)
    dia = diagnose(file, darker_target)
    try
        f(dia)
    finally
        close(dia)
    end
end
