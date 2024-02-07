using CodecLZO
using Documenter

DocMeta.setdocmeta!(CodecLZO, :DocTestSetup, :(using CodecLZO); recursive=true)

makedocs(;
    modules=[CodecLZO,CodecLZO.LZO],
    authors="Phil Killewald <reallyasi9@users.noreply.github.com> and contributors",
    repo="https://github.com/reallyasi9/CodecLZO.jl/blob/{commit}{path}#{line}",
    sitename="CodecLZO.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://reallyasi9.github.io/CodecLZO.jl",
        edit_link="development",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/reallyasi9/CodecLZO.jl",
    devbranch="development",
)
