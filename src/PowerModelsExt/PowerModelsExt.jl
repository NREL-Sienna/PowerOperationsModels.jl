module PowerModelsExt

import .InfrastructureModelsExt as _IM
import .InfrastructureModels: optimize_model!, @im_fields, nw_id_default
import InfrastructureSystems
import JuMP
import LinearAlgebra
import Logging
import SparseArrays

# Import base abstract type from InfrastructureSystems.Optimization
const AbstractPowerModel = InfrastructureSystems.Optimization.AbstractPowerModel

const _pm_global_keys = Set(["time_series", "per_unit"])
const pm_it_name = "pm"
const pm_it_sym = Symbol(pm_it_name)

include("core/data.jl")
include("core/ref.jl")
include("core/base.jl")
include("core/types.jl")
include("core/variable.jl")
include("core/constraint_template.jl")
include("core/constraint.jl")
include("core/expression_template.jl")
include("core/relaxation_scheme.jl")
include("core/objective.jl")
include("core/solution.jl")
include("form/iv.jl")

include("form/acp.jl")
include("form/acr.jl")
include("form/act.jl")
include("form/apo.jl")
include("form/dcp.jl")
include("form/lpac.jl")
include("form/bf.jl")
include("form/wr.jl")
include("form/wrm.jl")
include("form/shared.jl")

include("prob/opb.jl")
include("prob/pf_bf.jl")
include("prob/pf_iv.jl")
include("prob/opf.jl")
include("prob/opf_bf.jl")
include("prob/opf_iv.jl")
include("prob/ots.jl")
# include("prob/test.jl")

include("util/obbt.jl")
include("util/flow_limit_cuts.jl")

# this must come last to support automated export
include("core/export.jl")

# This import was retained for anyone using PowerModelsExt.InfrastructureModels.
# The suggested approach is for users to import InfrastructureModels in their
# own code.
import InfrastructureModels

end  # module PowerModelsExt
