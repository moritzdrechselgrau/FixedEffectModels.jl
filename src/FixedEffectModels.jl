
module FixedEffectModels


using DataFrames
using FixedEffects
using LinearAlgebra
using Printf
using Reexport
using SnoopPrecompile 
using Statistics
using StatsAPI
using StatsBase
using StatsFuns
@reexport using StatsModels
using Tables
using Vcov

include("utils/fixedeffects.jl")
include("utils/basecol.jl")
include("utils/tss.jl")
include("utils/formula.jl")
include("FixedEffectModel.jl")
include("fit.jl")
include("partial_out.jl")

# Export from StatsBase
export coef, coefnames, coeftable, responsename, vcov, stderror, nobs, dof_residual, r2, adjr2, islinear, deviance, rss, mss, confint, predict, residuals, fit

export reg,
partial_out,
fe,
FixedEffectModel,
has_iv,
has_fe,
Vcov


@precompile_all_calls begin
    df = DataFrame(x1 = [1.0, 2.0, 3.0, 4.0], x2 = [1.0, 2.0, 4.0, 4.0], y = [3.0, 4.0, 4.0, 5.0], id = [1, 1, 2, 2])
    reg(df, @formula(y ~ x1 + x2))
    reg(df, @formula(y ~ x1 + fe(id)))
    reg(df, @formula(y ~ 1), Vcov.cluster(:id))
end




end
