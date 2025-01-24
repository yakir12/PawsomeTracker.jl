function findfirstfont()
    for c in 'a':'z'
        face = findfont(string(c))
        if !isnothing(face)
            return face
        end
    end
    return nothing
end

nextpair(x::Int) = isodd(x) ? x + 1 : x

struct Diagnose
    label::String
    face::FTFont
    writer::VideoWriter
    buffer::Matrix{Gray{N0f8}}
    ratio::Int

    function Diagnose(file, sz)
        label = first(splitext(basename(file)))
        ratio = 8
        buff_sz = nextpair.(sz .÷ ratio)
        buffer = Matrix{Gray{N0f8}}(undef, buff_sz...)
        writer = open_video_out(file, buffer)
        face = findfirstfont()
        new(label, face, writer, buffer, ratio)
    end
end

struct Dont end

diagnose(file, img) = Diagnose(file, img)
diagnose(::Nothing, img) = Dont()


function diagnose(f, file, img)
    dia = diagnose(file, img)
    try
        f(dia)
    finally
        close(dia)
    end
end

Base.close(dia::Diagnose) = close_video_out!(dia.writer)
Base.close(::Dont) = nothing

function (dia::Diagnose)(img, point)
    imresize!(dia.buffer, img)
    draw!(dia.buffer, CirclePointRadius(CartesianIndex(point .÷ dia.ratio), 2))
    renderstring!(dia.buffer, dia.label, dia.face, 10, 10, 10, halign=:hleft, valign = :vtop)
    write(dia.writer, dia.buffer)
end
(::Dont)(_, _) = nothing


