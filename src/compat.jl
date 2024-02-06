# MIT License
# Copyright (c) 2009-2023: Jeff Bezanson, Stefan Karpinski, Viral B. Shah, and other contributors: https://github.com/JuliaLang/julia/contributors
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# end of terms and conditions

"""
    circshift!(src, shifts)

Circularly shift, i.e., rotate, the data in `src` in place. `shifts` specifies the amount to shift.

!!! compat
    This in-place circular shift is not defined in Julia < 1.7. This method is copied from the Julia source code. It will be removed when the LTS is bumped to >= 1.7.
"""
# one-argument circshift is not defined for Julia < 1.7
# TODO: remove this when LTS is bumped.
# Copied from Julia 1.7+::
function circshift!(v::AbstractVector, i::Integer)
    length(v) == 0 && return v
    i = mod(i, length(v))
    i == 0 && return v
    l = lastindex(v)
    reverse!(v, firstindex(v), l - i)
    reverse!(v, l - i + 1, l)
    reverse!(v)
    return v
end