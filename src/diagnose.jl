
nextpair(x::Int) = isodd(x) ? x + 1 : x

struct Diagnose
    label::String
    face::FTFont
    writer::VideoWriter
    buffer::Matrix{Gray{N0f8}}
    ratio::Int
    color::Gray{N0f8}

    function Diagnose(file, sz, darker_target)
        label = first(splitext(basename(file)))
        ratio = 8
        buff_sz = nextpair.(sz .÷ ratio)
        buffer = Matrix{Gray{N0f8}}(undef, buff_sz...)
        writer = open_video_out(file, buffer)
        face = PawsomeTracker.FTFont(joinpath(ASSETS, "TeXGyreHerosMakie-Regular.otf"))
        color = darker_target ? Gray{N0f8}(1) : Gray{N0f8}(0)
        new(label, face, writer, buffer, ratio, color)
    end
end

struct Dont end

diagnose(file, sz, darker_target) = Diagnose(file, sz, darker_target)
diagnose(::Nothing, _, _) = Dont()


function diagnose(f, file, sz, darker_target)
    dia = diagnose(file, sz, darker_target)
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
    draw!(dia.buffer, CirclePointRadius(CartesianIndex(point .÷ dia.ratio), 1), dia.color)
    renderstring!(dia.buffer, dia.label, dia.face, 10, 10, 10, halign=:hleft, valign = :vtop)
    write(dia.writer, dia.buffer)
end
(::Dont)(_, _) = nothing


