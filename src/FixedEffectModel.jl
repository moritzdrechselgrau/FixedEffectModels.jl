
##############################################################################
##
## Type FixedEffectModel
##
##############################################################################

struct FixedEffectModel <: RegressionModel
    coef::Vector{Float64}   # Vector of coefficients
    vcov::Matrix{Float64}   # Covariance matrix
    vcov_type::CovarianceEstimator
    nclusters::Union{NamedTuple, Nothing}

    esample::BitVector      # Is the row of the original dataframe part of the estimation sample?
    residuals::Union{AbstractVector, Nothing}
    fe::DataFrame
    fekeys::Vector{Symbol}


    coefnames::Vector       # Name of coefficients
    responsename::Union{String, Symbol} # Name of dependent variable
    formula::FormulaTerm        # Original formula
    formula_schema::FormulaTerm # Schema for predict
    contrasts::Dict

    nobs::Int64             # Number of observations
    dof::Int64              # Number parameters estimated - has_intercept
    dof_residual::Int64        # dof used for t-test and F-stat. nobs - degrees of freedoms with simple std

    rss::Float64            # Sum of squared residuals
    tss::Float64            # Total sum of squares
    r2::Float64             # R squared
    adjr2::Float64          # R squared adjusted

    F::Float64              # F statistics
    p::Float64              # p value for the F statistics

    # for FE
    iterations::Union{Int, Nothing}         # Number of iterations
    converged::Union{Bool, Nothing}         # Has the demeaning algorithm converged?
    r2_within::Union{Float64, Nothing}      # within r2 (with fixed effect

    # for IV
    F_kp::Union{Float64, Nothing}           # First Stage F statistics KP
    p_kp::Union{Float64, Nothing}           # First Stage p value KP
end

has_iv(m::FixedEffectModel) = m.F_kp !== nothing
has_fe(m::FixedEffectModel) = has_fe(m.formula)



StatsAPI.coef(m::FixedEffectModel) = m.coef
StatsAPI.coefnames(m::FixedEffectModel) = m.coefnames
StatsAPI.responsename(m::FixedEffectModel) = m.responsename
StatsAPI.vcov(m::FixedEffectModel) = m.vcov
StatsAPI.nobs(m::FixedEffectModel) = m.nobs
StatsAPI.dof(m::FixedEffectModel) = m.dof
StatsAPI.dof_residual(m::FixedEffectModel) = m.dof_residual
StatsAPI.r2(m::FixedEffectModel) = m.r2
StatsAPI.adjr2(m::FixedEffectModel) = m.adjr2
StatsAPI.islinear(m::FixedEffectModel) = true
StatsAPI.deviance(m::FixedEffectModel) = m.tss
StatsAPI.rss(m::FixedEffectModel) = m.rss
StatsAPI.mss(m::FixedEffectModel) = deviance(m) - rss(m)
StatsModels.formula(m::FixedEffectModel) = m.formula_schema

function StatsAPI.confint(m::FixedEffectModel; level::Real = 0.95)
    scale = tdistinvcdf(StatsAPI.dof_residual(m), 1 - (1 - level) / 2)
    se = stderror(m)
    hcat(m.coef -  scale * se, m.coef + scale * se)
end

# predict, residuals, modelresponse


function StatsAPI.predict(m::FixedEffectModel, data)
    Tables.istable(data) ||
          throw(ArgumentError("expected second argument to be a Table, got $(typeof(data))"))
    has_fe(m) &&
        throw("To predict for a model with high-dimensional fixed effects, run `reg` with the option save = true, and then access predicted values using `fe().")
    cdata = StatsModels.columntable(data)
    cols, nonmissings = StatsModels.missing_omit(cdata, m.formula_schema.rhs)
    Xnew = modelmatrix(m.formula_schema, cols)
    if all(nonmissings)
        out = Xnew * m.coef
    else
        out = Vector{Union{Float64, Missing}}(missing, length(Tables.rows(cdata)))
        out[nonmissings] = Xnew * m.coef 
    end

    # Join FE estimates onto data and sum row-wise
    # This code does not work propertly with missing or with interacted fixed effect, so deleted
    #if has_fe(m)
    #    df = DataFrame(t; copycols = false)
    #    fes = leftjoin(select(df, m.fekeys), unique(m.fe); on = m.fekeys, makeunique = true, #matchmissing = :equal)
    #    fes = combine(fes, AsTable(Not(m.fekeys)) => sum)
    #    out[nonmissings] .+= fes[nonmissings, 1]
    #end

    return out
end

function StatsAPI.residuals(m::FixedEffectModel, data)
    Tables.istable(data) ||
      throw(ArgumentError("expected second argument to be a Table, got $(typeof(data))"))
    has_fe(m) &&
     throw("To access residuals for a model with high-dimensional fixed effects,  run `reg` with the option save = :residuals, and then access residuals with `residuals()`.")
    cdata = StatsModels.columntable(data)
    cols, nonmissings = StatsModels.missing_omit(cdata, m.formula_schema.rhs)
    Xnew = modelmatrix(m.formula_schema, cols)
    y = response(m.formula_schema, cdata)
    if all(nonmissings)
        out =  y -  Xnew * m.coef
    else
        out = Vector{Union{Float64, Missing}}(missing,  length(Tables.rows(cdata)))
        out[nonmissings] = y -  Xnew * m.coef
    end
    return out
end


function StatsAPI.residuals(m::FixedEffectModel)
    if m.residuals === nothing
        has_fe(m) && throw("To access residuals in a fixed effect regression,  run `reg` with the option save = :residuals, and then access residuals with `residuals()`")
        !has_fe(m) && throw("To access residuals,  use residuals(m, data) where `m` is an estimated FixedEffectModel and  `data` is a Table")
    end
    m.residuals
end

"""
   fe(x::FixedEffectModel; keepkeys = false)

Return a DataFrame with fixed effects estimates.
The output is aligned with the original DataFrame used in `reg`.

### Keyword arguments
* `keepkeys::Bool' : Should the returned DataFrame include the original variables used to defined groups? Default to false
"""

function fe(m::FixedEffectModel; keepkeys = false)
   !has_fe(m) && throw("fe() is not defined for fixed effect models without fixed effects")
   if keepkeys
       m.fe
   else
      m.fe[!, (length(m.fekeys)+1):end]
   end
end


function StatsAPI.coeftable(m::FixedEffectModel; level = 0.95)
    cc = coef(m)
    se = stderror(m)
    coefnms = coefnames(m)
    conf_int = confint(m; level = level)
    # put (intercept) last
    if !isempty(coefnms) && ((coefnms[1] == Symbol("(Intercept)")) || (coefnms[1] == "(Intercept)"))
        newindex = vcat(2:length(cc), 1)
        cc = cc[newindex]
        se = se[newindex]
        conf_int = conf_int[newindex, :]
        coefnms = coefnms[newindex]
    end
    tt = cc ./ se
    CoefTable(
        hcat(cc, se, tt, fdistccdf.(Ref(1), Ref(StatsAPI.dof_residual(m)), abs2.(tt)), conf_int[:, 1:2]),
        ["Estimate","Std. Error","t-stat", "Pr(>|t|)", "Lower 95%", "Upper 95%" ],
        ["$(coefnms[i])" for i = 1:length(cc)], 4)
end


##############################################################################
##
## Display Result
##
##############################################################################

function top(m::FixedEffectModel)
    out = [
            "Number of obs" sprint(show, nobs(m), context = :compact => true);
            "Degrees of freedom" sprint(show, dof(m), context = :compact => true);
            "R²" @sprintf("%.3f",r2(m));
            "R² adjusted" @sprintf("%.3f",adjr2(m));
            "F-statistic" sprint(show, m.F, context = :compact => true);
            "P-value" @sprintf("%.3f",m.p);
            ]
    if has_iv(m)
        out = vcat(out, 
            [
                "F-statistic (first stage)" sprint(show, m.F_kp, context = :compact => true);
                "P-value (first stage)" @sprintf("%.3f",m.p_kp);
            ])
    end
    if has_fe(m)
        out = vcat(out, 
            [
                "R² within" @sprintf("%.3f",m.r2_within);
                "Iterations" sprint(show, m.iterations, context = :compact => true);
             ])
    end
    return out
end



import StatsBase: NoQuote, PValue
function Base.show(io::IO, m::FixedEffectModel)
    ct = coeftable(m)
    #copied from show(iio,cf::Coeftable)
    cols = ct.cols; rownms = ct.rownms; colnms = ct.colnms;
    nc = length(cols)
    nr = length(cols[1])
    if length(rownms) == 0
        rownms = [lpad("[$i]",floor(Integer, log10(nr))+3) for i in 1:nr]
    end
    mat = [j == 1 ? NoQuote(rownms[i]) :
           j-1 == ct.pvalcol ? NoQuote(sprint(show, PValue(cols[j-1][i]))) :
           j-1 in ct.teststatcol ? TestStat(cols[j-1][i]) :
           cols[j-1][i] isa AbstractString ? NoQuote(cols[j-1][i]) : cols[j-1][i]
           for i in 1:nr, j in 1:nc+1]
    io = IOContext(io, :compact=>true, :limit=>false)
    A = Base.alignment(io, mat, 1:size(mat, 1), 1:size(mat, 2),
                       typemax(Int), typemax(Int), 3)
    nmswidths = pushfirst!(length.(colnms), 0)
    A = [nmswidths[i] > sum(A[i]) ? (A[i][1]+nmswidths[i]-sum(A[i]), A[i][2]) : A[i]
         for i in 1:length(A)]
    totwidth = sum(sum.(A)) + 2 * (length(A) - 1)


    #intert my stuff which requires totwidth
    ctitle = string(typeof(m))
    halfwidth = div(totwidth - length(ctitle), 2)
    print(io, " " ^ halfwidth * ctitle * " " ^ halfwidth)
    ctop = top(m)
    for i in 1:size(ctop, 1)
        ctop[i, 1] = ctop[i, 1] * ":"
    end
    println(io, '\n', repeat('=', totwidth))
    halfwidth = div(totwidth, 2) - 1
    interwidth = 2 +  mod(totwidth, 2)
    for i in 1:(div(size(ctop, 1) - 1, 2)+1)
        print(io, ctop[2*i-1, 1])
        print(io, lpad(ctop[2*i-1, 2], halfwidth - length(ctop[2*i-1, 1])))
        print(io, " " ^interwidth)
        if size(ctop, 1) >= 2*i
            print(io, ctop[2*i, 1])
            print(io, lpad(ctop[2*i, 2], halfwidth - length(ctop[2*i, 1])))
        end
        println(io)
    end
   
    # rest of coeftable code
    println(io, repeat('=', totwidth))
    print(io, repeat(' ', sum(A[1])))
    for j in 1:length(colnms)
        print(io, "  ", lpad(colnms[j], sum(A[j+1])))
    end
    println(io, '\n', repeat('─', totwidth))
    for i in 1:size(mat, 1)
        Base.print_matrix_row(io, mat, A, i, 1:size(mat, 2), "  ")
        i != size(mat, 1) && println(io)
    end
    println(io, '\n', repeat('=', totwidth))
    nothing
end
 

##############################################################################
##
## Schema
##
##############################################################################
function StatsModels.apply_schema(t::FormulaTerm, schema::StatsModels.Schema, Mod::Type{FixedEffectModel}, has_fe_intercept)
    schema = StatsModels.FullRank(schema)
    if has_fe_intercept
        push!(schema.already, InterceptTerm{true}())
    end
    FormulaTerm(apply_schema(t.lhs, schema.schema, StatisticalModel),
                StatsModels.collect_matrix_terms(apply_schema(t.rhs, schema, StatisticalModel)))
end

