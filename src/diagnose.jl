struct Diagnose
    label::String
    buffer::Matrix{Gray{N0f8}}
    color::Gray{N0f8}
    writer::VideoWriter

    function Diagnose(file, darker_target)
        label = first(splitext(basename(file)))
        buff_sz = (360, 640)
        buffer = Matrix{Gray{N0f8}}(undef, buff_sz...)
        color = darker_target ? Gray{N0f8}(1) : Gray{N0f8}(0)
        writer = open_video_out(file, buffer)
        new(label, buffer, color, writer)
    end
end
diagnose(file::AbstractString, darker_target::Bool) = Diagnose(file, darker_target)

function (dia::Diagnose)(img, point)
    draw!(img, CirclePointRadius(CartesianIndex(point), 5), dia.color)
    imresize!(dia.buffer, img)
    renderstring!(dia.buffer, dia.label, FACE[], 10, 10, 10, halign=:hleft, valign = :vtop)
    write(dia.writer, dia.buffer)
end

Base.close(dia::Diagnose) = close_video_out!(dia.writer)

struct Dont end
diagnose(::Nothing, _) = Dont()
(::Dont)(_, _) = nothing
Base.close(::Dont) = nothing

function diagnose(f, file, darker_target)
    dia = diagnose(file, darker_target)
    try
        f(dia)
    finally
        close(dia)
    end
end
