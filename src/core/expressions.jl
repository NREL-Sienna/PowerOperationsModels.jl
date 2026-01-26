# POM-specific expression types
# Base expression types (SystemBalanceExpressions, CostExpressions, etc.) are imported from IOM

# POM-specific abstract type for post-contingency system balance expressions
abstract type PostContingencySystemBalanceExpressions <: SystemBalanceExpressions end

# POM-specific concrete types
struct PostContingencyActivePowerBalance <: PostContingencySystemBalanceExpressions end
struct ComponentReserveUpBalanceExpression <: ExpressionType end
struct ComponentReserveDownBalanceExpression <: ExpressionType end
struct InterfaceTotalFlow <: ExpressionType end
struct PTDFBranchFlow <: ExpressionType end
struct PostContingencyNodalActivePowerDeployment <: PostContingencyExpressions end

# Method extensions for result writing
should_write_resulting_value(::Type{InterfaceTotalFlow}) = true
should_write_resulting_value(::Type{PTDFBranchFlow}) = true

# Method extensions for unit conversion
convert_result_to_natural_units(::Type{InterfaceTotalFlow}) = true
convert_result_to_natural_units(::Type{PostContingencyBranchFlow}) = true
convert_result_to_natural_units(::Type{PostContingencyActivePowerGeneration}) = true
convert_result_to_natural_units(::Type{PTDFBranchFlow}) = true
