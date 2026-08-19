"""
Return an empty `JuMP.AffExpr` whose term dictionary is pre-sized for `size` terms.
"""
function get_hinted_aff_expr(size::Int)
    expr = JuMP.AffExpr(0.0)
    sizehint!(expr.terms, size)
    return expr
end
