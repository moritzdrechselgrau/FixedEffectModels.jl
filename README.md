[![Build status](https://github.com/FixedEffects/FixedEffectModels.jl/workflows/CI/badge.svg)](https://github.com/FixedEffects/FixedEffectModels.jl/actions)

This package estimates linear models with high dimensional categorical variables and/or instrumental variables.

## Installation
The package is registered in the [`General`](https://github.com/JuliaRegistries/General) registry and so can be installed at the REPL with `] add FixedEffectModels`.

## Benchmarks
The objective of the package is similar to the Stata command [`reghdfe`](https://github.com/sergiocorreia/reghdfe) and the R packages [`lfe`](https://cran.r-project.org/web/packages/lfe/lfe.pdf) and [`fixest`](https://lrberge.github.io/fixest/). The package is much faster than `reghdfe` or `lfe`. It also tends to be a bit faster than the more recent `fixest` (depending on the exact command). For complicated models, `FixedEffectModels` can also run on Nvidia GPUs for even faster performances (see below)


![benchmark](http://www.matthieugomez.com/files/fixedeffectmodels_benchmark.png)

## Syntax

```julia
using DataFrames, RDatasets, FixedEffectModels
df = dataset("plm", "Cigar")
reg(df, @formula(Sales ~ NDI + fe(State) + fe(Year)), Vcov.cluster(:State), weights = :Pop)
# =====================================================================
# Number of obs:               1380   Degrees of freedom:            32
# R2:                         0.803   R2 Adjusted:                0.798
# F Statistic:              13.3382   p-value:                    0.001
# R2 within:                  0.139   Iterations:                     6
# Converged:                   true
# =====================================================================
#         Estimate  Std.Error  t value Pr(>|t|)   Lower 95%   Upper 95%
# ---------------------------------------------------------------------
# NDI  -0.00526264 0.00144097 -3.65216    0.000 -0.00808942 -0.00243586
# =====================================================================
```


-  A typical formula is composed of one dependent variable, exogeneous variables, endogeneous variables, instrumental variables, and a set of high-dimensional fixed effects.

	```julia
	dependent variable ~ exogenous variables + (endogenous variables ~ instrumental variables) + fe(fixedeffect variable)
	```

	High-dimensional fixed effect variables are indicated with the function `fe`.  You can add an arbitrary number of high dimensional fixed effects, separated with `+`. You can also interact fixed effects using `&` or `*`.

	For instance, to add state fixed effects use `fe(State)`. To add both state and year fixed effects, use `fe(State) + fe(Year)`. To add state-year fixed effects, use `fe(State)&fe(Year)`. To add state specific slopes for year, use `fe(State)&Year`. To add both state fixed-effects and state specific slopes for year use `fe(State)*Year`.

	```julia
	reg(df, @formula(Sales ~ Price + fe(State) + fe(Year)))
	reg(df, @formula(Sales ~ NDI + fe(State) + fe(State)&Year))
	reg(df, @formula(Sales ~ NDI + fe(State)&fe(Year)))              # for illustration only (this will not run here)
	reg(df, @formula(Sales ~ (Price ~ Pimin)))
	```

	To construct formula programatically, use
	```julia
	reg(df, term(:Sales) ~ term(:NDI) + fe(:State) + fe(:Year))
	```

- The option `contrasts` specifies that a column should be understood as a set of dummy variables:
	```julia
	reg(df, @formula(Sales ~ Price + Year); contrasts = Dict(:Year => DummyCoding()))
	```
	You can specify different base levels 
	```julia
	reg(df, @formula(Sales ~ Price + Year); contrasts = Dict(:Year => DummyCoding(base = 80)))
	```


- The option `weights` specifies a variable for weights
	```julia
	weights = :Pop
	```

- Standard errors are indicated with the prefix `Vcov` (with the package [Vcov](http://github.com/matthieugomez/Vcov.jl))
	```julia
	Vcov.robust()
	Vcov.cluster(:State)
	Vcov.cluster(:State, :Year)
	```

- The option `save` can be set to one of the following:  `none` (default) to save nothing `:residuals` to save residuals, `:fe` to save fixed effects. You can access the result with `residuals()` and `fe()`

- The option `method` can be set to one of the following: `:cpu`, `:gpu` (see Performances below).


## Output
`reg` returns a light object. It is composed of

  - the vector of coefficients & the covariance matrix (use `coef`, `coefnames`, `vcov` on the output of `reg`)
  - a boolean vector reporting rows used in the estimation
  - a set of scalars (number of observations, the degree of freedoms, r2, etc)
  - with the option `save = true`, a dataframe aligned with the initial dataframe with residuals and, if the model contains high dimensional fixed effects, fixed effects estimates (use `residuals` or `fe` on the output of `reg`)


Methods such as `predict`, `residuals` are still defined but require to specify a dataframe as a second argument.  The problematic size of `lm` and `glm` models in R or Julia is discussed [here](http://www.r-bloggers.com/trimming-the-fat-from-glm-models-in-r/), [here](https://blogs.oracle.com/R/entry/is_the_size_of_your), [here](http://stackoverflow.com/questions/21896265/how-to-minimize-size-of-object-of-class-lm-without-compromising-it-being-passe) [here](http://stackoverflow.com/questions/15260429/is-there-a-way-to-compress-an-lm-class-for-later-prediction) (and for absurd consequences, [here](http://stackoverflow.com/questions/26010742/using-stargazer-with-memory-greedy-glm-objects) and [there](http://stackoverflow.com/questions/22577161/not-enough-ram-to-run-stargazer-the-normal-way)).


You may use [RegressionTables.jl](https://github.com/jmboehm/RegressionTables.jl) to get publication-quality regression tables.


## Performances

### MultiThreads
`FixedEffectModels` is multi-threaded. Use the option `nthreads` to select the number of threads to use in the estimation (defaults to `Threads.nthreads()`).

### Nvidia GPU
The package has support for Nvidia GPUs  (thanks to Paul Schrimpf). This can make the package an order of magnitude faster for complicated problems.

If you have a Nvidia GPU, run `using CUDA` before `using FixedEffectModels`. Then, estimate a model with `method = :gpu`. For maximum speed, set the floating point precision to `Float32` with `double_precision = false`.

```julia
using CUDA, FixedEffectModels
df = dataset("plm", "Cigar")
reg(df, @formula(Sales ~ NDI + fe(State) + fe(Year)), method = :gpu, double_precision = false)
```


## Solution Method
Denote the model `y = X β + D θ + e` where X is a matrix with few columns and D is the design matrix from categorical variables. Estimates for `β`, along with their standard errors, are obtained in two steps:

1. `y, X`  are regressed on `D` using the package [FixedEffects.jl](https://github.com/FixedEffects/FixedEffects.jl)
2.  Estimates for `β`, along with their standard errors, are obtained by regressing the projected `y` on the projected `X` (an application of the Frisch Waugh-Lovell Theorem)
3. With the option `save = true`, estimates for the high dimensional fixed effects are obtained after regressing the residuals of the full model minus the residuals of the partialed out models on `D` using the package [FixedEffects.jl](https://github.com/FixedEffects/FixedEffects.jl)

# References

Baum, C. and Schaffer, M. (2013) *AVAR: Stata module to perform asymptotic covariance estimation for iid and non-iid data robust to heteroskedasticity, autocorrelation, 1- and 2-way clustering, and common cross-panel autocorrelated disturbances*. Statistical Software Components, Boston College Department of Economics.

Correia, S. (2014) *REGHDFE: Stata module to perform linear or instrumental-variable regression absorbing any number of high-dimensional fixed effects*. Statistical Software Components, Boston College Department of Economics.

Fong, DC. and Saunders, M. (2011) *LSMR: An Iterative Algorithm for Sparse Least-Squares Problems*.  SIAM Journal on Scientific Computing

Gaure, S. (2013) *OLS with Multiple High Dimensional Category Variables*. Computational Statistics and Data Analysis
