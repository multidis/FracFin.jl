######### Estimators for fractional processes #########


#### Rolling window ####

"""
Rolling window estimator for 1d or multivariate time series.

# Args
- func: estimator
- X0: input, 1d or 2d array with each column being one observation
- p: step of the rolling window
- (w,d,n): size of sample vector; length of decorrelation (no effect if `n==1`); number of sample vectors per window

# Returns
- array of estimations on the rolling window

# Notes
The estimator is applied on a rolling window every `p` steps. The rolling window is divided into `n` (possibly overlapping) sub-windows of size `w` at the pace `d`, such that the size of the rolling window equals to `(n-1)*d+w`. In this way the data on a rolling window is put into a new matrix of dimension `w*q`-by-`n` for q-variates time series, and its columns are the column-concatenantions of data on the sub-window. Moreover, different columns of this new matrix are assumed as i.i.d. observations.
"""
function rolling_estim(func::Function, X0::AbstractVecOrMat{T}, p::Int, (w,d,n)::Tuple{Int,Int,Int}; mode::Symbol=:causal) where {T<:Real}
    L = (n-1)*d + w  # size of rolling window
    res = []
    X = reshape(X0, ndims(X0)>1 ? size(X0,1) : 1, :)  # vec to matrix, create a reference not a copy
    
    if mode == :causal
        for t = size(X,2):-p:1
            xs = hcat([X[:,(t-i-w+1):(t-i)][:] for i in d*(n-1:-1:0) if t-i>=w]...)  # X[:] creates a copy
            if length(xs) > 0
                pushfirst!(res, (t,func(xs)))
            end
        end
        # return [func(X[n+widx]) for n=1:p:length(X) if n+widx[end]<length(X)]
    else
        for t = 1:p:size(X,2)-L+1
            xs = hcat([X[:, (t+i):(t+i+w-1)][:] for i in d*(0:n-1) if t+i+w-1<=length(X)]...)
            if length(xs) > 0
                push!(res, (t,func(xs)))
            end
        end
    end
    return res
end


# function rolling_estim(func::Function, X::AbstractMatrix{T}, widx::AbstractArray{Int}, p::Int) where {T<:Real}
#     # wsize = w[end]-w[1]+1
#     # @assert wsize <= size(X,2)
#     return [func(X[:,n+widx]) for n=1:p:size(X,2) if n+widx[end]<size(X,2)]
#     # res = []
#     # for n=1:p:size(X,2)
#     #     idx = n+w
#     #     idx = idx[idx.<=size(X,2)]
#     #     push!(res, func(view(X, :,n+w)))
#     # end
# end


# function rolling_estim(fun::Function, X::AbstractVector{T}, wsize::Int, p::Int=1) where T
#     offset = wsize-1
#     res = [fun(view(X, (n*p):(n*p+wsize-1))) for n=1:p:N]
#     end

#     # y = fun(view(X, idx:idx+offset))  # test return type of fun
#     res = Vector{typeof(y)}(undef, div(length(data)-offset, p))
#     @inbounds for n=1:p:N
#         push!(res, fun(view(X, (idx*p):(idx*p+offset))))
#         end
#     @inbounds for n in eachindex(res)
#         res[n] = fun(hcat(X[idx*p:idx*p+offset]...))
#     end

#     return res
# end


######## Estimators for fBm ########

"""
Compute the p-th moment of the increment of time-lag `d` of a 1d array.
"""
moment_incr(X,d,p) = mean((abs.(X[d+1:end] - X[1:end-d])).^p)


"""
Power-law estimator for Hurst exponent and volatility.

# Args
- X: sample path
- lags: array of the increment step
- p: power

# Returns
- (hurst, σ), ols: estimation of Hurst and volatility, as well as the GLM ols object.
"""
function fBm_powlaw_estim(X::AbstractVector{T}, lags::AbstractArray{Int}, p::T=2.) where {T<:Real}
    @assert length(lags) > 1 && all(lags .> 1)

    C = 2^(p/2) * gamma((p+1)/2)/sqrt(pi)

    yp = map(d -> log(moment_incr(X, d, p)), lags)
    xp = p * log.(lags)
    
    # estimation of H and β
    # by manual inversion
    # Ap = hcat(xp, ones(length(xp))) # design matrix
    # hurst, β = Ap \ yp
    # or by GLM
    dg = DataFrames.DataFrame(xvar=xp, yvar=yp)
    ols = GLM.lm(@GLM.formula(yvar~xvar), dg)
    β, hurst = GLM.coef(ols)

    σ = exp((β-log(C))/p)

    return (hurst, σ), ols
end


##### Generalized scalogram #####

"""
B-Spline scalogram estimator for Hurst exponent and volatility.

# Args
- S: vector of scalogram, ie, variance of the wavelet coefficients per scale.
- sclrng: scale of wavelet transform. Each number in `sclrng` corresponds to one row in the matrix X
- v: vanishing moments
"""
function fBm_bspline_scalogram_estim(S::AbstractVector{T}, sclrng::AbstractArray{Int}, v::Int; mode::Symbol=:center) where {T<:Real}
    @assert length(S) == length(sclrng)

    df = DataFrames.DataFrame(xvar=log.(sclrng.^2), yvar=log.(S))
    ols = GLM.lm(@GLM.formula(yvar~xvar), df)
    coef = GLM.coef(ols)

    hurst = coef[2]-1/2
    # println(hurst)
    C1 = C1rho(0, 1, hurst, v, mode)
    σ = exp((coef[1] - log(abs(C1)))/2)
    return (hurst, σ), ols

    # Ar = hcat(xr, ones(length(xr)))  # design matrix
    # H0, η = Ar \ yr  # estimation of H and β
    # hurst = H0-1/2
    # C1 = C1rho(0, r, hurst, v, mode)
    # σ = ℯ^((η - log(abs(C1)))/2)
    # return hurst, σ
end

function fBm_bspline_scalogram_estim(W::AbstractMatrix{T}, sclrng::AbstractArray{Int}, v::Int; dims::Int=1, mode::Symbol=:center) where {T<:Real}
    return fBm_bspline_scalogram_estim(var(W,dims), sclrng, v; mode=mode)        
end

function fBm_bspline_scalogram_estim(W::AbstractVector{T}, sclrng::AbstractArray{Int}, v::Int; mode::Symbol=:center) where {T<:AbstractVector{<:Real}}
    return fBm_bspline_scalogram_estim([var(w) for w in W], sclrng, v; mode=mode)
end

"""
Generalized B-Spline scalogram estimator for Hurst exponent and volatility.

# Args
- Σ: covariance matrix of wavelet coefficients.
- sclrng: scale of wavelet transform. Each number in `sclrng` corresponds to one row in the matrix X
- v: vanishing moments
- r: rational ratio defining a line in the covariance matrix, e.g. r=1 corresponds to the main diagonal.
"""
function fBm_gen_bspline_scalogram_estim(Σ::AbstractMatrix{T}, sclrng::AbstractArray{Int}, v::Int, r::Rational=1//1; mode::Symbol=:center) where {T<:Real}
    @assert issymmetric(Σ)
    @assert size(Σ,1) == length(sclrng)
    @assert r >= 1
    if r > 1
        all(diff(sclrng/sclrng[1]) .== 1) || error("Imcompatible scales: the ratio between the k-th and the 1st scale must be k")
    end

    p,q,N = r.num, r.den, length(sclrng)
    @assert N>=2p

    # Σ = cov(X, X, dims=2, corrected=true)  # covariance matrix

    yr = [log(abs(Σ[q*j, p*j])) for j in 1:N if p*j<=N]
    xr = [log(sclrng[q*j] * sclrng[p*j]) for j in 1:N if p*j<=N]

    df = DataFrames.DataFrame(xvar=xr, yvar=yr)
    ols = GLM.lm(@GLM.formula(yvar~xvar), df)
    coef = GLM.coef(ols)

    hurst = coef[2]-1/2
    # println(hurst)
    C1 = C1rho(0, r, hurst, v, mode)
    σ = exp((coef[1] - log(abs(C1)))/2)
    return (hurst, σ), ols

    # Ar = hcat(xr, ones(length(xr)))  # design matrix
    # H0, η = Ar \ yr  # estimation of H and β
    # hurst = H0-1/2
    # C1 = C1rho(0, r, hurst, v, mode)
    # σ = ℯ^((η - log(abs(C1)))/2)
    # return hurst, σ
end




##### MLE #####

# abstract type Estimator end

# abstract type MaximumLikelihoodEstimator <: Estimator end
# const MLE = MaximumLikelihoodEstimator

# struct fGnMLE <: MLE
# end

# struct WaveletMLE <: MLE
# end


# function estim(E::Estimator, X::AbstractVecOrMat)
#     nothing
# end


# function estim(E::MaximumLikelihoodEstimator, X::AbstractVecOrMat, wobs::Int, dlen::Int)
#     nothing
# end



"""
Safe evaluation of the inverse quadratic form
    trace(X' * inv(A) * X)
where the matrix A is symmetric and positive definite.
"""
function xiAx(A::AbstractMatrix{T}, X::AbstractVecOrMat{T}, ε::Real=0) where {T<:Real}
    @assert issymmetric(A)
    @assert size(X, 1) == size(A, 1)

    S, U = eigen(A)  # so that U * Diagonal(S) * inv(U) == A, in particular, U' == inv(U)
    idx = (S .> ε)

    # U, S, V = svd(A)
    # idx = S .> ε
    return sum((U[:,idx]'*X).^2 ./ S[idx])
end

# function xiAx(A::AbstractMatrix{T}, X::AbstractVecOrMat{T}, ε::Real=0) where {T<:Real}
#     @assert issymmetric(A)
#     @assert size(X, 1) == size(A, 1)

#     iA = pinv(A)
#     return tr(X' * iA * X)
# end


"""
Safe evaluation of the log-likelihood of a fBm model with the implicit optimal volatility (in the MLE sense).

The value of log-likelihood (up to some additif constant) is
    -1/2 * (N*log(X'*inv(A)*X) + logdet(A))

# Args
- A: covariance matrix, must be symmetric and positive definite
- X: vector of matrix of observation

# Notes
- This function is common to all MLEs with the covariance matrix of form σ²A(h), where {σ, h} are unknown parameters. This kind of MLE can be carried out in h uniquely and σ is obtained from h.
"""
function log_likelihood_H(A::AbstractMatrix{T}, X::AbstractVecOrMat{T}, ε::Real=0) where {T<:Real}
    @assert issymmetric(A)
    @assert size(X, 1) == size(A, 1)

    N = ndims(X)>1 ? size(X,2) : 1
    # d = size(X,1), such that N*d == length(X)

    S, U = eigen(A)  # so that U * Diagonal(S) * inv(U) == A, in particular, U' == inv(U)
    idx = (S .> ε)
    # U, S, V = svd(A)
    # idx = S .> ε
    return -1/2 * (length(X)*log(sum((U[:,idx]'*X).^2 ./ S[idx])) + N*sum(log.(S[idx])))
end

# function log_likelihood_H(A::AbstractMatrix{T}, X::AbstractVecOrMat{T}, ε::Real=0) where {T<:Real}
#     @assert issymmetric(A)
#     @assert size(X, 1) == size(A, 1)

#     N = ndims(X)>1 ? size(X,2) : 1
#     # d = size(X,1), such that N*d == length(X)

#     return -1/2 * (length(X)*log(xiAx(A,X)) + N*logdet(A))
# end


function fGn_log_likelihood_H(X::AbstractVecOrMat{T}, H::Real) where {T<:Real}
    @assert 0 < H < 1
    Σ = Matrix(Symmetric(covmat(FractionalGaussianNoise(H, 1.), size(X,1))))
    return log_likelihood_H(Σ, X)
end

"""
fGn-MLE of Hurst exponent and volatility.

# Args
- X: observation vector or matrix. For matrix input each column is an i.i.d. observation.
- method: :optim for optimization based or :table for look-up table based solution.
- ε: this defines the bounded constraint [ε, 1-ε], and for method==:table this is also the step of search for Hurst exponent.

# Notes
- This method is computationally expensive for long observations (say, >= 500 points). In this case the 1d data should be divided into i.i.d. short observations and put into a matrix format. 
"""
function fGn_MLE_estim(X::AbstractVecOrMat{T}; method::Symbol=:optim, ε::Real=1e-2) where {T<:Real}
    # @assert 0. < ε < 1. && Nh >= 1
    func = h -> -fGn_log_likelihood_H(X, h)

    opm = nothing
    hurst = nothing

    if method == :optim
        # Gradient-free constrained optimization
        opm = Optim.optimize(func, ε, 1-ε, Optim.Brent())
        # # Gradient-based optimization
        # optimizer = Optim.GradientDescent()  # e.g. Optim.BFGS(), Optim.GradientDescent()
        # opm = Optim.optimize(func, ε, 1-ε, [0.5], Optim.Fminbox(optimizer))
        hurst = Optim.minimizer(opm)[1]
    elseif method == :table    
        Hs = collect(ε:ε:1-ε)
        L = [func(h) for h in Hs]
        hurst = Hs[argmin(L)]
    else
        throw("Unknown method: ", method)
    end
    
    Σ = Matrix(Symmetric(covmat(FractionalGaussianNoise(hurst, 1.), size(X,1))))
    σ = sqrt(xiAx(Σ, X) / length(X))

    return (hurst, σ), opm
end


function fGn_MLL_estim(X::AbstractVecOrMat{T}; ε::Real=0.01) where {T<:Real}
    @assert 0. < ε < 1.
    func = h -> -fGn_log_likelihood_H(X, h)
    L = [func(X, h) for h in ε:ε:1-ε]
    
end

##### Wavelet-MLE #####

"""
Compute the covariance matrix of B-Spline DCWT coefficients of a pure fBm.

The full covariance matrix of `J`-scale transform and of time-lag `N` is a N*J-by-N*J symmetric matrix.

# Args
- l: maximum time-lag
- sclrng: scale range
- v: vanishing moments of B-Spline wavelet
- H: Hurst exponent
- mode: mode of convolution
"""
function fBm_bspline_covmat(l::Int, sclrng::AbstractArray{Int}, v::Int, H::Real, mode::Symbol)
    J = length(sclrng)
    A = [sqrt(i*j) for i in sclrng, j in sclrng].^(2H+1)
    Σs = [[C1rho(d/sqrt(i*j), j/i, H, v, mode) for i in sclrng, j in sclrng] .* A for d = 0:l]

    Σ = zeros(((l+1)*J, (l+1)*J))
    for r = 0:l
        for c = 0:l
            Σ[(r*J+1):(r*J+J), (c*J+1):(c*J+J)] = (c>=r) ? Σs[c-r+1] : transpose(Σs[r-c+1])
        end
    end

    return Matrix(Symmetric(Σ))  #  forcing symmetry
    # return [(c>=r) ? Σs[c-r+1] : Σs[r-c+1]' for r=0:N-1, c=0:N-1]
end


"""
Evaluate the log-likelihood of B-Spline DCWT coefficients.
"""
function fBm_bspline_log_likelihood_H(X::AbstractVecOrMat{T}, sclrng::AbstractArray{Int}, v::Int, H::Real, mode::Symbol) where {T<:Real}
    @assert 0 < H < 1
    @assert size(X,1) % length(sclrng) == 0

    L = size(X,1) ÷ length(sclrng)  # integer division: \div
    # N = ndims(X)>1 ? size(X,2) : 1

    Σ = full_bspline_covmat(L-1, sclrng, v, H, mode)  # full covariance matrix

    # # strangely, the following does not work (logarithm of a negative value)
    # iΣ = pinv(Σ)  # regularization by pseudo-inverse
    # return -1/2 * (J*N*log(trace(X'*iΣ*X)) + logdet(Σ))

    return log_likelihood_H(Σ, X)
end


"""
B-Spline wavelet-MLE estimator.
"""
function fBm_bspline_MLE_estim(X::AbstractVecOrMat{T}, sclrng::AbstractArray{Int}, v::Int; init::Real=0.5, ε::Real=1e-3, mode::Symbol=:center) where {T<:Real}
    @assert size(X,1) % length(sclrng) == 0

    L = size(X,1) ÷ length(sclrng)  # integer division: \div
    # N = ndims(X)>1 ? size(X,2) : 1

    func = x -> -full_bspline_log_likelihood_H(X, sclrng, v, x[1], mode)

    # # Gradient based
    # # optimizer = Optim.GradientDescent()  # e.g. Optim.BFGS(), Optim.GradientDescent()
    # optimizer = Optim.BFGS()
    # opm = Optim.optimize(func, [ε], [1-ε], [0.5], Optim.Fminbox(optimizer))

    # Non-gradient based
    optimizer = Optim.Brent()
    # optimizer = Optim.GoldenSection()
    opm = Optim.optimize(func, ε, 1-ε, optimizer)

    hurst = Optim.minimizer(opm)[1]

    Σ = full_bspline_covmat(L-1, sclrng, v, hurst, mode)
    σ = sqrt(xiAx(Σ, X) / length(X))

    return (hurst, σ), opm
end


# function partial_bspline_covmat(sclrng::AbstractArray{Int}, v::Int, H::Real, mode::Symbol)
#     return full_bspline_covmat(0, sclrng, v, H, mode)
# end


# function partial_bspline_log_likelihood_H(X::AbstractVecOrMat{T}, sclrng::AbstractArray{Int}, v::Int, H::Real; mode::Symbol=:center) where {T<:Real}
#     # @assert size(X,1) == length(sclrng)
#     Σ = partial_bspline_covmat(sclrng, v, H, mode)
#     # println(size(Σ))
#     # println(size(X))

#     return log_likelihood_H(Σ, X)
# end


# """
# B-Spline wavelet-MLE estimator with partial covariance matrix.
# """
# function partial_bspline_MLE_estim(X::AbstractVecOrMat{T}, sclrng::AbstractArray{Int}, v::Int; init::Real=0.5, mode::Symbol=:center) where {T<:Real}
#     @assert size(X,1) == length(sclrng)

#     func = h -> -partial_bspline_log_likelihood_H(X, sclrng, v, h; mode=mode)

#     ε = 1e-5
#     # optimizer = Optim.GradientDescent()  # e.g. Optim.BFGS(), Optim.GradientDescent()
#     # optimizer = Optim.BFGS()
#     # opm = Optim.optimize(func, ε, 1-ε, [0.5], Optim.Fminbox(optimizer))
#     opm = Optim.optimize(func, ε, 1-ε, Optim.Brent())

#     hurst = Optim.minimizer(opm)[1]

#     Σ = partial_bspline_covmat(sclrng, v, hurst, mode)
#     σ = sqrt(xiAx(Σ, X) / length(X))

#     return (hurst, σ), opm
# end






function partial_wavelet_log_likelihood_H(X::Matrix{Float64}, sclrng::AbstractArray{Int}, v::Int, H::Real; mode::Symbol=:center)
    N, J = size(X)  # length and dim of X

    A = [sqrt(i*j) for i in sclrng, j in sclrng].^(2H+1)
    Σ = [C1rho(0, j/i, H, v, mode) for i in sclrng, j in sclrng] .* A

    iΣ = pinv(Σ)  # regularization by pseudo-inverse

    return -1/2 * (J*N*log(sum(X' .* (iΣ * X'))) + N*logdet(Σ))
end


function partial_wavelet_MLE_obj(X::Matrix{Float64}, sclrng::AbstractArray{Int}, v::Int, H::Real, σ::Real; mode::Symbol=:center)
    N, d = size(X)  # length and dim of X

    A = [sqrt(i*j) for i in sclrng, j in sclrng].^(2H+1)
    C1 = [C1rho(0, j/i, H, v, mode) for i in sclrng, j in sclrng]

    Σ = σ^2 * C1 .* A
    # Σ += Matrix(1.0I, size(Σ)) * max(1e-10, mean(abs.(Σ))*1e-5)

    # println("H=$(H), σ=$(σ), mean(Σ)=$(mean(abs.(Σ)))")
    # println("logdet(Σ)=$(logdet(Σ))")

    # method 1:
    # iX = Σ \ X'

    # method 2:
    iΣ = pinv(Σ)  # regularization by pseudo-inverse
    iX = iΣ * X'  # regularization by pseudo-inverse

    # # method 3:
    # iX = lsqr(Σ, X')

    return -1/2 * (tr(X*iX) + N*logdet(Σ) + N*d*log(2π))
end


# function wavelet_MLE_obj(X::Matrix{Float64}, sclrng::AbstractArray{Int}, v::Int, H::Real, σ::Real; mode::Symbol=:center)
#     N, d = size(X)  # length and dim of X

#     A = [sqrt(i*j) for i in sclrng, j in sclrng].^(2H+1)
#     C1 = [C1rho(0, j/i, H, v, mode) for i in sclrng, j in sclrng]

#     Σ = σ^2 * C1 .* A
#     # Σ += Matrix(1.0I, size(Σ)) * max(1e-10, mean(abs.(Σ))*1e-5)

#     # println("H=$(H), σ=$(σ), mean(Σ)=$(mean(abs.(Σ)))")
#     # println("logdet(Σ)=$(logdet(Σ))")

#     # method 1:
#     # iX = Σ \ X'

#     # method 2:
#     iΣ = pinv(Σ)  # regularization by pseudo-inverse
#     iX = iΣ * X'  # regularization by pseudo-inverse

#     # # method 3:
#     # iX = lsqr(Σ, X')

#     return -1/2 * (tr(X*iX) + N*logdet(Σ) + N*d*log(2π))
# end


# older version:
# function wavelet_MLE_obj(X::Matrix{Float64}, sclrng::AbstractArray{Int}, v::Int, α::Real, β::Real; cflag::Bool=false, mode::Symbol=:center)
#     N, d = size(X)  # length and dim of X

#     H = cflag ? sigmoid(α) : α
#     σ = cflag ? exp(β) : β

#     A = [sqrt(i*j) for i in sclrng, j in sclrng].^(2H+1)
#     C1 = [C1rho(0, j/i, H, v, mode) for i in sclrng, j in sclrng]

#     Σ = σ^2 * C1 .* A
#     # Σ += Matrix(1.0I, size(Σ)) * max(1e-8, mean(abs.(Σ))*1e-5)

#     # println("H=$(H), σ=$(σ), α=$(α), β=$(β), mean(Σ)=$(mean(abs.(Σ)))")
#     # println("logdet(Σ)=$(logdet(Σ))")

#     # method 1:
#     # iX = Σ \ X'

#     # # method 2:
#     # iΣ = pinv(Σ)  # regularization by pseudo-inverse
#     # iX = iΣ * X'  # regularization by pseudo-inverse

#     # method 3:
#     iX = lsqr(Σ, X')

#     return -1/2 * (tr(X*iX) + N*log(abs(det(Σ))) + N*d*log(2π))
# end


# function grad_wavelet_MLE_obj(X::Matrix{Float64}, sclrng::AbstractArray{Int}, v::Int, α::Real, β::Real; cflag::Bool=false, mode::Symbol=:center)
#     N, d = size(X)  # length and dim of X

#     H = cflag ? sigmoid(α) : α
#     σ = cflag ? exp(β) : β

#     A = [sqrt(i*j) for i in sclrng, j in sclrng].^(2H+1)
#     C1 = [C1rho(0, j/i, H, v, mode) for i in sclrng, j in sclrng]
#     dAda = [log(i*j) for i in sclrng, j in sclrng] .* A
#     dC1da = [diff_C1rho(0, j/i, H, v, mode) for i in sclrng, j in sclrng]

#     if cflag
#         dAda *= diff_sigmoid(α)
#         dC1da *= diff_sigmoid(α)
#     end

#     Σ = σ^2 * C1 .* A
#     # Σ += Matrix(1.0I, size(Σ)) * max(1e-8, mean(abs.(Σ))*1e-5)
#     dΣda = σ^2 * (dC1da .* A + C1 .* dAda)
#     dΣdb = cflag ? 2*Σ : 2σ * C1 .* A

#     # method 1:
#     # iX = Σ \ X'
#     # da = N * tr(Σ \ dΣda) - tr(iX' * dΣda * iX)
#     # db = N * tr(Σ \ dΣdb) - tr(iX' * dΣdb * iX)

#     # method 2:
#     iΣ = pinv(Σ)  # regularization by pseudo-inverse
#     iX = iΣ * X'
#     da = N * tr(iΣ * dΣda) - tr(iX' * dΣda * iX)
#     db = N * tr(iΣ * dΣdb) - tr(iX' * dΣdb * iX)

#     # method 3:
#     # iX = lsqr(Σ, X')
#     # da = N * tr(lsqr(Σ, dΣda)) - tr(iX' * dΣda * iX)
#     # db = N * tr(lsqr(Σ, dΣdb)) - tr(iX' * dΣdb * iX)

#     return  -1/2 * [da, db]
# end


function wavelet_MLE_estim(X::Matrix{Float64}, sclrng::AbstractArray{Int}, v::Int; vars::Symbol=:all, init::Vector{Float64}=[0.5,1.], mode::Symbol=:center)
    @assert size(X,2) == length(sclrng)
    @assert length(init) == 2

    func = x -> ()
    hurst, σ = init
    # println(init)

    if vars == :all
        func = x -> -wavelet_MLE_obj(X, sclrng, v, x[1], x[2]; mode=mode)
    elseif vars == :hurst
        func = x -> -wavelet_MLE_obj(X, sclrng, v, x[1], σ; mode=mode)
    else
        func = x -> -wavelet_MLE_obj(X, sclrng, v, hurst, x[2]; mode=mode)
    end

    ε = 1e-8
    # optimizer = Optim.GradientDescent()  # e.g. Optim.BFGS(), Optim.GradientDescent()
    optimizer = Optim.BFGS()
    opm = Optim.optimize(func, [ε, ε], [1-ε, 1/ε], init, Optim.Fminbox(optimizer))
    # opm = Optim.optimize(func, [ε, ε], [1-ε, 1/ε], init, Optim.Fminbox(optimizer); autodiff=:forward)
    res = Optim.minimizer(opm)

    if vars == :all
        hurst, σ = res[1], res[2]
    elseif vars == :hurst
        hurst = res[1]
    else
        σ = res[2]
    end

    return (hurst, σ), opm
end

