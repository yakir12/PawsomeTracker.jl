
nextpair(x::Int) = isodd(x) ? x + 1 : x

struct Diagnose
    label::String
    face::FTFont
    writer::VideoWriter
    buffer::Matrix{Gray{N0f8}}
    color::Gray{N0f8}

    function Diagnose(file, darker_target)
        label = first(splitext(basename(file)))
        # buff_sz = nextpair.(sz .÷ ratio)
        buff_sz = (360, 640)
        # ratio = 8
        buffer = Matrix{Gray{N0f8}}(undef, buff_sz...)
        writer = open_video_out(file, buffer)
        face = PawsomeTracker.FTFont(joinpath(ASSETS, "TeXGyreHerosMakie-Regular.otf"))
        color = darker_target ? Gray{N0f8}(1) : Gray{N0f8}(0)
        new(label, face, writer, buffer, color)
    end
end

struct Dont end

diagnose(file, darker_target) = Diagnose(file, darker_target)
diagnose(::Nothing, _) = Dont()


function diagnose(f, file, darker_target)
    dia = diagnose(file, darker_target)
    try
        f(dia)
    finally
        close(dia)
    end
end

Base.close(dia::Diagnose) = close_video_out!(dia.writer)
Base.close(::Dont) = nothing

function (dia::Diagnose)(img, point)
    draw!(img, CirclePointRadius(CartesianIndex(point), 5), dia.color)
    imresize!(dia.buffer, img)
    renderstring!(dia.buffer, dia.label, dia.face, 10, 10, 10, halign=:hleft, valign = :vtop)
    write(dia.writer, dia.buffer)
end
(::Dont)(_, _) = nothing


