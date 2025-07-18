/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2025, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package NFCeval

import Binding = NFBinding;
import ComponentRef = NFComponentRef;
import Error;
import Component = NFComponent;
import Expression = NFExpression;
import NFInstNode.InstNode;
import Operator = NFOperator;
import NFOperator.Op;
import Typing = NFTyping;
import Call = NFCall;
import Dimension = NFDimension;
import Type = NFType;
import ExpressionSimplify;
import NFPrefixes.{Variability, Purity};
import NFClassTree.ClassTree;
import ComplexType = NFComplexType;
import Subscript = NFSubscript;
import NFTyping.TypingError;
import Record = NFRecord;
import InstContext = NFInstContext;

protected
import NFFunction.Function;
import EvalFunction = NFEvalFunction;
import List;
import System;
import ExpressionIterator = NFExpressionIterator;
import MetaModelica.Dangerous.*;
import Class = NFClass;
import TypeCheck = NFTypeCheck;
import ExpandExp = NFExpandExp;
import Prefixes = NFPrefixes;
import SimplifyExp = NFSimplifyExp;
import UnorderedMap;
import ErrorExt;
import Array;
import Vector;

public
uniontype EvalTarget
  record EVAL_TARGET
    SourceInfo info;
    InstContext.Type context;
    Option<EvalTargetData> extra;
  end EVAL_TARGET;

  function new
    input SourceInfo info;
    input InstContext.Type context = NFInstContext.NO_CONTEXT;
    input Option<EvalTargetData> extra = NONE();
    output EvalTarget target = EVAL_TARGET(info, context, extra);
  end new;

  function hasInfo
    input EvalTarget target;
    output Boolean res = not stringEmpty(target.info.fileName);
  end hasInfo;

  function getInfo
    input EvalTarget target;
    output SourceInfo info = target.info;
  end getInfo;
end EvalTarget;

constant EvalTarget noTarget = EvalTarget.EVAL_TARGET(AbsynUtil.dummyInfo, NFInstContext.NO_CONTEXT, NONE());

uniontype EvalTargetData
  record DIMENSION_DATA
    InstNode component;
    Integer index;
    Expression exp;
  end DIMENSION_DATA;
end EvalTargetData;

function tryEvalExp
  input output Expression exp;
algorithm
  ErrorExt.setCheckpoint(getInstanceName());

  try
    exp := evalExp(exp);
  else
  end try;

  ErrorExt.rollBack(getInstanceName());
end tryEvalExp;

function evalExp
  input output Expression exp;
  input EvalTarget target = noTarget;
algorithm
  exp := match exp
    local
      InstNode c;
      Binding binding;
      Expression exp1, exp2, exp3;
      Call call;
      Component comp;
      Option<Expression> oexp;
      ComponentRef cref;
      Dimension dim;

    case Expression.CREF()
      then evalCref(exp.cref, exp, target);

    case Expression.TYPENAME()
      then evalTypename(exp.ty, exp, target);

    case Expression.ARRAY()
      then if exp.literal then exp
           else
             Expression.makeArrayCheckLiteral(exp.ty,
               Array.map(exp.elements, function evalExp(target = target)));

    case Expression.RANGE() then evalRange(exp, target);

    case Expression.TUPLE()
      algorithm
        exp.elements := list(evalExp(e, target) for e in exp.elements);
      then
        exp;

    case Expression.RECORD()
      algorithm
        exp.elements := list(evalExp(e, target) for e in exp.elements);
      then
        exp;

    case Expression.CALL()
      then evalCall(exp.call, target);

    case Expression.SIZE()
      then evalSize(exp.exp, exp.dimIndex, target);

    case Expression.BINARY()
      algorithm
        exp1 := evalExp(exp.exp1, target);
        exp2 := evalExp(exp.exp2, target);
      then
        evalBinaryOp(exp1, exp.operator, exp2, target);

    // TODO
    // case Expression.MULTARY()

    case Expression.UNARY()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then
        evalUnaryOp(exp1, exp.operator);

    case Expression.LBINARY()
      algorithm
        exp1 := evalExp(exp.exp1, target);

        if Expression.isSplitSubscriptedExp(exp1) then
          exp2 := evalExp(exp.exp2, target);
        else
          exp2 := exp.exp2;
        end if;
      then
        evalLogicBinaryOp(exp1, exp.operator, exp2, target);

    case Expression.LUNARY()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then
        evalLogicUnaryOp(exp1, exp.operator);

    case Expression.RELATION()
      algorithm
        exp1 := evalExp(exp.exp1, target);
        exp2 := evalExp(exp.exp2, target);
      then
        evalRelationOp(exp1, exp.operator, exp2);

    case Expression.IF() then evalIfExp(exp, target);

    case Expression.CAST()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then
        evalCast(exp1, exp.ty);

    case Expression.UNBOX()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then Expression.UNBOX(exp1, exp.ty);

    case Expression.SUBSCRIPTED_EXP()
      then evalSubscriptedExp(exp.exp, exp.subscripts, target);

    case Expression.TUPLE_ELEMENT()
      algorithm
        exp1 := evalExp(exp.tupleExp, target);
      then
        Expression.tupleElement(exp1, exp.ty, exp.index);

    case Expression.RECORD_ELEMENT()
      then evalRecordElement(exp, target);

    case Expression.MUTABLE()
      algorithm
        exp1 := evalExp(Mutable.access(exp.exp), target);
      then
        exp1;

    else exp;
  end match;
end evalExp;

function evalExpPartialDefault
  "Simplied version of evalExpPartial to work around MetaModelica issues with
   default arguments and multiple return values when used as a function pointer."
  input output Expression exp;
algorithm
  exp := evalExpPartial(exp);
end evalExpPartialDefault;

function evalExpPartial
  "Evaluates the parts of an expression that are possible to evaluate. This
   means leaving parts of the expression that contains e.g. iterators or mutable
   expressions. This can be used to optimize an expression that is expected to
   be evaluated many times, for example the expression in an array constructor."
  input Expression exp;
  input EvalTarget target = noTarget;
  input Boolean evaluated = true;
  output Expression outExp;
  output Boolean outEvaluated "True if the whole expression is evaluated, otherwise false.";
protected
  Expression e, e1, e2;
  Boolean eval1, eval2;
algorithm
  (e, outEvaluated) :=
    Expression.mapFoldShallow(exp, function evalExpPartial(target = target), true);

  outExp := match e
    case Expression.CREF()
      algorithm
        if ComponentRef.isIterator(e.cref) then
          // Don't evaluate iterators.
          outExp := e;
          outEvaluated := false;
        else
          // Crefs can be evaluated even if they have non-evaluated subscripts.
          outExp := evalCref(e.cref, e, target, evalSubscripts = false);
          outEvaluated := Expression.isLiteral(outExp);
        end if;
      then
        outExp;

    // Don't evaluate mutable expressions. While they could technically be
    // evaluated they're usually used as mutable iterators.
    case Expression.MUTABLE()
      algorithm
        outEvaluated := false;
      then
        e;

    else if outEvaluated then evalExp(e, target) else e;
  end match;

  outEvaluated := evaluated and outEvaluated;
end evalExpPartial;

function evalCref
  input ComponentRef cref;
  input Expression defaultExp;
  input EvalTarget target;
  input Boolean evalSubscripts = true;
  input Boolean liftExp = true;
  output Expression exp;
protected
  InstNode c;
  Boolean evaled;
  list<Subscript> subs;
algorithm
  exp := match cref
    case ComponentRef.CREF(node = c as InstNode.COMPONENT_NODE())
      guard not ComponentRef.isIterator(cref) and
            ComponentRef.nodeVariability(cref) < Variability.NON_STRUCTURAL_PARAMETER
      then evalComponentBinding(c, cref, defaultExp, target, evalSubscripts, liftExp);

    else defaultExp;
  end match;
end evalCref;

function evalComponentBinding
  input InstNode node;
  input ComponentRef cref;
  input Expression defaultExp "The expression returned if the binding couldn't be evaluated";
  input EvalTarget target;
  input Boolean evalSubscripts = true;
  input Boolean liftExp = false "Ensure that the result has the same dimensions as the cref";
  output Expression exp;
protected
  InstContext.Type exp_context;
  Component comp;
  Binding binding;
  Boolean evaluated;
  list<Subscript> subs;
  Variability var;
  Option<Expression> start_exp;
  Type cref_ty, exp_ty;
  Integer dim_diff;
algorithm
  exp_context := InstContext.nodeContext(node, target.context);
  Typing.typeComponentBinding(node, exp_context, typeChildren = false);
  comp := InstNode.component(node);
  binding := Component.getBinding(comp);

  if Binding.isUnbound(binding) then
    // In some cases we need to construct a binding for the node, for example when
    // a record has bindings on the fields but not on the record instance as a whole.
    binding := makeComponentBinding(comp, node, Expression.toCref(defaultExp), target);

    if Binding.isUnbound(binding) then
      // If we couldn't construct a binding, try to use the start value instead.
      start_exp := evalComponentStartBinding(node, comp, cref, target, evalSubscripts);

      if isSome(start_exp) then
        // The component had a valid start value. The value has already been
        // evaluated by evalComponentStartBinding, so skip the rest of the function.
        SOME(exp) := start_exp;
        return;
      end if;
    end if;
  end if;

  (exp, evaluated) := match binding
    case Binding.TYPED_BINDING()
      algorithm
        exp := match Mutable.access(binding.evalState)
          // A not yet evaluated binding.
          case NFBinding.EvalState.NOT_EVALUATED
            algorithm
              // Mark the binding as currently being evaluated, to detect loops due
              // to mutually dependent constants/parameters.
              Mutable.update(binding.evalState, NFBinding.EvalState.EVALUATING);

              // Evaluate the binding expression.
              try
                exp := evalExp(binding.bindingExp, target);
              else
                // Reset the flag if the evaluation failed.
                Mutable.update(binding.evalState, NFBinding.EvalState.NOT_EVALUATED);
                fail();
              end try;

              // Update the binding expression in the component and mark the
              // binding as evaluated.
              binding.bindingExp := exp;
              comp := Component.setBinding(binding, comp);
              InstNode.updateComponent(comp, node);
              Mutable.update(binding.evalState, NFBinding.EvalState.EVALUATED);
            then
              exp;

          // An already evaluated binding.
          case NFBinding.EvalState.EVALUATED then binding.bindingExp;

          // A binding that's being evaluated => evaluation loop.
          else
            algorithm
              Error.addSourceMessage(Error.CIRCULAR_PARAM,
                {InstNode.name(node), Prefixes.variabilityString(Component.variability(comp))},
                InstNode.info(node));
            then
              fail();
        end match;
      then
        (exp, true);

    case Binding.CEVAL_BINDING() then (binding.bindingExp, true);

    case Binding.UNBOUND()
      algorithm
        printUnboundError(comp, target, defaultExp);
      then
        (defaultExp, false);

    else
      algorithm
        Error.addInternalError(getInstanceName() + " failed on untyped binding", sourceInfo());
      then
        fail();

  end match;

  // Apply subscripts from the cref to the binding expression as needed.
  if evaluated then
    exp := subscriptBinding(exp, cref, evalSubscripts);
  end if;

  if liftExp and not Expression.contains(exp, Expression.isSplitSubscriptedExp) then
    exp_ty := Expression.typeOf(exp);
    cref_ty := Expression.typeOf(defaultExp);
    dim_diff := Type.dimensionDiff(cref_ty, exp_ty);

    if dim_diff > 0 then
      exp := Expression.liftArrayList(List.firstN(Type.arrayDims(cref_ty), dim_diff), exp);
    end if;
  end if;
end evalComponentBinding;

function subscriptBinding
  input output Expression exp;
  input ComponentRef cref;
  input Boolean evalSubscripts;
protected
  list<Subscript> subs;
algorithm
  subs := ComponentRef.getSubscripts(cref);

  if evalSubscripts then
    subs := list(Subscript.eval(s) for s in subs);
  end if;

  subs := List.trimToLength(subs, Expression.dimensionCount(exp));
  exp := Expression.applySubscripts(subs, exp);
  exp := subscriptBinding2(exp, cref, evalSubscripts, NONE());
end subscriptBinding;

function subscriptBinding2
  input output Expression exp;
  input ComponentRef cref;
  input Boolean evalSubscripts;
  input output Option<UnorderedMap<InstNode, list<Subscript>>> subMap;
protected
  type SubscriptList = list<Subscript>;
  UnorderedMap<InstNode, list<Subscript>> sub_map;
  list<Subscript> subs;
  list<ComponentRef> cref_parts;
  Expression e;
algorithm
  (exp, subMap) := match exp
    case Expression.SUBSCRIPTED_EXP(subscripts = subs)
      algorithm
        if isSome(subMap) then
          SOME(sub_map) := subMap;
        else
          // If the cref hasn't been flattened then subscripts that reference
          // the scope parts of the cref should be kept as they are, so the
          // scope isn't added to the map in that case.
          cref_parts := ComponentRef.toListReverse(cref, includeScope = isFlatCref(cref));

          // Create a map that maps each part of the cref to the subscripts on that part.
          sub_map := UnorderedMap.new<SubscriptList>(InstNode.hash,
            InstNode.refEqual, Util.nextPrime(listLength(cref_parts)));

          for cr in cref_parts loop
            UnorderedMap.addUnique(ComponentRef.node(cr), ComponentRef.getSubscripts(cr), sub_map);
          end for;

          subMap := SOME(sub_map);
        end if;

        // Replace the split subscripts with the corresponding subscripts from the cref.
        subs := list(subscriptBinding3(s, sub_map) for s in subs);

        // Evaluate the subscripts if it was requested.
        if evalSubscripts then
          subs := list(Subscript.eval(s) for s in subs);
        end if;

        (e, subMap) := subscriptBinding2(exp.exp, cref, evalSubscripts, subMap);
        e := Expression.applySubscripts(subs, e);
      then
        (e, subMap);

    case Expression.ARRAY(literal = true) then (exp, subMap);

    else Expression.mapFoldShallow(exp,
      function subscriptBinding2(cref = cref, evalSubscripts = evalSubscripts), subMap);

  end match;
end subscriptBinding2;

function isFlatCref
  input ComponentRef cref;
  output Boolean flat;
algorithm
  flat := match cref
    // A cref is considered to be flat if the first part that comes from the
    // scope and has an array type also has subscripts. A cref with only scalars
    // in the scope part may technically be flat, but it doesn't matter since
    // there won't be any subscripts referencing them anyway.
    case ComponentRef.CREF(origin = NFComponentRef.Origin.SCOPE)
      guard Type.isArray(cref.ty)
      then not listEmpty(cref.subscripts);

    case ComponentRef.CREF() then isFlatCref(cref.restCref);
    else false;
  end match;
end isFlatCref;

function subscriptBinding3
  input Subscript subscript;
  input UnorderedMap<InstNode, list<Subscript>> subMap;
  output Subscript outSubscript;
protected
  Option<list<Subscript>> osubs;
  list<Subscript> subs;
algorithm
  outSubscript := match subscript
    case Subscript.SPLIT_INDEX()
      algorithm
        osubs := UnorderedMap.get(subscript.node, subMap);

        if isSome(osubs) then
          SOME(subs) := osubs;

          if subscript.dimIndex > listLength(subs) then
            outSubscript := Subscript.WHOLE();
          else
            outSubscript := listGet(subs, subscript.dimIndex);
          end if;
        else
          outSubscript := subscript;
        end if;
      then
        outSubscript;

    else subscript;
  end match;
end subscriptBinding3;

function evalComponentStartBinding
  "Tries to evaluate the given component's start value. NONE() is returned if
   the component isn't a fixed parameter or if it doesn't have a start value.
   Otherwise the evaluated binding expression is returned if it could be
   evaluated, or the function will fail if it couldn't be."
  input InstNode node;
  input Component comp;
  input ComponentRef cref;
  input EvalTarget target;
  input Boolean evalSubscripts;
  output Option<Expression> outExp = NONE();
protected
  Variability var;
  InstNode start_node;
  Component start_comp;
  Binding binding;
  Expression exp;
  list<Subscript> subs;
  Integer pcount;
algorithm
  // Only use the start value if the component is a fixed parameter.
  var := Component.variability(comp);
  if (var <> Variability.PARAMETER and var <> Variability.STRUCTURAL_PARAMETER) or
     not Component.isFixed(comp) then
    return;
  end if;

  // Look up "start" in the class.
  try
    start_node := Class.lookupElement("start", InstNode.getClass(node));
  else
    return;
  end try;

  // Make sure we have an actual start attribute, and didn't just find some
  // other element named start in the class.
  start_comp := InstNode.component(start_node);
  if not Component.isTypeAttribute(start_comp) then
    return;
  end if;

  // Try to evaluate the binding if one exists.
  binding := Component.getBinding(start_comp);

  outExp := match binding
    case Binding.TYPED_BINDING()
      algorithm
        exp := evalExp(binding.bindingExp, target);

        if not referenceEq(exp, binding.bindingExp) then
          binding.bindingExp := exp;
          start_comp := Component.setBinding(binding, start_comp);
          InstNode.updateComponent(start_comp, start_node);
        end if;
      then
        SOME(exp);

    else outExp;
  end match;
end evalComponentStartBinding;

function makeComponentBinding
  input Component component;
  input InstNode node;
  input ComponentRef cref;
  input EvalTarget target;
  output Binding binding;
protected
  Type ty;
  InstNode rec_node;
  Expression exp;
algorithm
  binding := matchcontinue component
    // A record field without an explicit binding, evaluate the parent's binding
    // if it has one and fetch the binding from it instead.
    case _
      algorithm
        exp := makeRecordFieldBindingFromParent(cref, target);
      then
        if Expression.isEmpty(exp) then NFBinding.EMPTY_BINDING else Binding.CEVAL_BINDING(exp);

    // A record component without an explicit binding, create one from its children.
    case Component.COMPONENT(ty = Type.COMPLEX(complexTy = ComplexType.RECORD(rec_node)))
      algorithm
        exp := makeRecordBindingExp(component.classInst, rec_node, component.ty, cref, target);
        binding := Binding.CEVAL_BINDING(exp);

        if not ComponentRef.hasSubscripts(cref) then
          InstNode.updateComponent(Component.setBinding(binding, component), node);
        end if;
      then
        binding;

    // A record array component without an explicit binding, create one from its children.
    case Component.COMPONENT(ty = Type.ARRAY(elementType = ty as
        Type.COMPLEX(complexTy = ComplexType.RECORD(rec_node))))
      algorithm
        exp := Expression.mapCrefScalars(Expression.fromCref(cref),
          function makeRecordBindingExp(typeNode = component.classInst,
            recordNode = rec_node, recordType = ty, target = target));

        binding := Binding.CEVAL_BINDING(exp);

        if not ComponentRef.hasSubscripts(cref) then
          InstNode.updateComponent(Component.setBinding(binding, component), node);
        end if;
      then
        binding;

    else NFBinding.EMPTY_BINDING;
  end matchcontinue;
end makeComponentBinding;

function makeRecordFieldBindingFromParent
  input ComponentRef cref;
  input EvalTarget target;
  output Expression exp;
protected
  ComponentRef parent_cr;
  InstNode parent;
  InstContext.Type exp_context;
  Binding binding;
  Component comp;
  list<Subscript> subs;
algorithm
  parent_cr := ComponentRef.rest(cref);
  parent := ComponentRef.node(parent_cr);
  exp_context := InstContext.nodeContext(parent, target.context);

  comp := InstNode.component(parent);
  binding := Component.getBinding(comp);
  subs := ComponentRef.getSubscripts(parent_cr);

  if Binding.hasExp(binding) then
    if not Binding.isTyped(binding) then
      binding := Typing.typeBinding(binding, InstContext.set(exp_context, NFInstContext.BINDING));
      comp := Component.setBinding(binding, comp);
      InstNode.updateComponent(comp, parent);
    end if;

    exp := Binding.getExp(binding);
    exp := Expression.applySubscripts(subs, exp);
    exp := Expression.recordElement(ComponentRef.firstName(cref), exp);
    exp := evalExp(exp, target);

    exp := Expression.map(exp, function Expression.expandNonListedSplitIndices(
      indicesToKeep = ComponentRef.nodesIncludingSplitSubs(cref)));
  else
    // If the parent didn't have a binding, try the parent's parent.
    exp := makeRecordFieldBindingFromParent(parent_cr, target);
    exp := Expression.applySubscripts(subs, exp);
    exp := Expression.recordElement(ComponentRef.firstName(cref), exp);
  end if;
end makeRecordFieldBindingFromParent;

function makeRecordBindingExp
  input InstNode typeNode;
  input InstNode recordNode;
  input Type recordType;
  input ComponentRef cref;
  input EvalTarget target;
  output Expression exp;
protected
  ClassTree tree;
  array<InstNode> comps;
  list<Expression> args;
  Type ty;
  InstNode c;
  ComponentRef cr;
  Expression arg;
algorithm
  tree := Class.classTree(InstNode.getClass(typeNode));
  comps := ClassTree.getComponents(tree);
  args := {};

  ErrorExt.setCheckpoint(getInstanceName());
  for i in arrayLength(comps):-1:1 loop
    c := comps[i];
    ty := InstNode.getType(c);
    cr := ComponentRef.CREF(c, {}, ty, NFComponentRef.Origin.CREF, cref);
    arg := Expression.CREF(ty, cr);

    if Component.variability(InstNode.component(c)) <= Variability.PARAMETER then
      try
        arg := evalExp(arg, target);
      else
        // Ignore components that don't have a binding, it might not be an error
        // and if it is we can give better error messages in other places.
        arg := Expression.EMPTY(ty);
      end try;
    end if;

    args := arg :: args;
  end for;
  ErrorExt.rollBack(getInstanceName());

  exp := Expression.makeRecord(InstNode.fullPath(recordNode), recordType, args);
end makeRecordBindingExp;

function evalTypename
  input Type ty;
  input Expression originExp;
  input EvalTarget target;
  output Expression exp;
algorithm
  // Only expand the typename into an array if it's used as a range, and keep
  // them as typenames when used as e.g. dimensions.
  exp := if InstContext.inIterationRange(target.context) then ExpandExp.expandTypename(ty) else originExp;
end evalTypename;

function evalRange
  input Expression rangeExp;
  input EvalTarget target;
  output Expression result;
protected
  Type ty;
  Expression start_exp, stop_exp;
  Option<Expression> step_exp;
  Expression max_prop_exp;
  Integer max_prop_count;
algorithm
  Expression.RANGE(ty = ty, start = start_exp, step = step_exp, stop = stop_exp) := rangeExp;
  start_exp := evalExp(start_exp, target);
  step_exp := Util.applyOption(step_exp, function evalExp(target = target));
  stop_exp := evalExp(stop_exp, target);

  if InstContext.inIterationRange(target.context) then
    ty := TypeCheck.getRangeType(start_exp, step_exp, stop_exp,
      Type.arrayElementType(ty), EvalTarget.getInfo(target));
    result := Expression.RANGE(ty, start_exp, step_exp, stop_exp);
  else
    result := Expression.RANGE(ty, start_exp, step_exp, stop_exp);
    result := Expression.mapSplitExpressions(result, evalRangeExp);
  end if;
end evalRange;

function evalRangeExp
  input Expression rangeExp;
  output Expression exp;
protected
  Expression start, step, stop;
  Option<Expression> opt_step;
  list<Expression> expl;
  Type ty;
  list<String> literals;
  Integer istep;
algorithm
  Expression.RANGE(start = start, step = opt_step, stop = stop) := SimplifyExp.simplify(Expression.map(rangeExp, Expression.replaceResizableParameter));

  if isSome(opt_step) then
    SOME(step) := opt_step;

    (ty, expl) := match (start, step, stop)
      case (Expression.INTEGER(), Expression.INTEGER(istep), Expression.INTEGER())
        algorithm
          // The compiler decided to randomly dislike using step.value here, hence istep.
          expl := list(Expression.INTEGER(i) for i in start.value:istep:stop.value);
        then
          (Type.INTEGER(), expl);

      case (Expression.REAL(), Expression.REAL(), Expression.REAL())
        algorithm
          expl := evalRangeReal(start.value, step.value, stop.value);
        then
          (Type.REAL(), expl);

      else
        algorithm
          printWrongArgsError(getInstanceName(), {start, step, stop}, sourceInfo());
        then
          fail();
    end match;
  else
    (ty, expl) := match (start, stop)
      case (Expression.INTEGER(), Expression.INTEGER())
        algorithm
          expl := list(Expression.INTEGER(i) for i in start.value:stop.value);
        then
          (Type.INTEGER(), expl);

      case (Expression.REAL(), Expression.REAL())
        algorithm
          expl := evalRangeReal(start.value, 1.0, stop.value);
        then
          (Type.REAL(), expl);

      case (Expression.BOOLEAN(), Expression.BOOLEAN())
        algorithm
          expl := list(Expression.BOOLEAN(b) for b in start.value:stop.value);
        then
          (Type.BOOLEAN(), expl);

      case (Expression.ENUM_LITERAL(ty = ty as Type.ENUMERATION()), Expression.ENUM_LITERAL())
        algorithm
          expl := list(Expression.ENUM_LITERAL(ty, listGet(ty.literals, i), i) for i in start.index:stop.index);
        then
          (ty, expl);

      else
        algorithm
          printWrongArgsError(getInstanceName(), {start, stop}, sourceInfo());
        then
          fail();
    end match;
  end if;

  exp := Expression.makeArray(Type.ARRAY(ty, {Dimension.fromInteger(listLength(expl))}),
                              listArray(expl), literal = true);
end evalRangeExp;

function evalRangeReal
  input Real start;
  input Real step;
  input Real stop;
  output list<Expression> result;
protected
  Integer steps;
algorithm
  steps := Util.realRangeSize(start, step, stop);

  // Real ranges are tricky, make sure that start and stop are reproduced
  // exactly if they are part of the range.
  if steps == 0 then
    result := {};
  elseif steps == 1 then
    result := {Expression.REAL(start)};
  else
    result := {Expression.REAL(stop)};
    for i in steps-2:-1:1 loop
      result := Expression.REAL(start + i * step) :: result;
    end for;
    result := Expression.REAL(start) :: result;
  end if;
end evalRangeReal;

function printFailedEvalError
  input String name;
  input Expression exp;
  input SourceInfo info;
algorithm
  Error.addInternalError(name + " failed to evaluate ‘" + Expression.toString(exp) + "‘", info);
end printFailedEvalError;

function evalBinaryOp
  input Expression exp1;
  input Operator op;
  input Expression exp2;
  input EvalTarget target = noTarget;
  output Expression exp;
algorithm
  exp := Expression.mapSplitExpressions(Expression.BINARY(exp1, op, exp2),
    function evalBinaryExp(target = target));
end evalBinaryOp;

function evalBinaryExp
  input Expression binaryExp;
  input EvalTarget target;
  output Expression result;
protected
  Expression e1, e2;
  Operator op;
algorithm
  Expression.BINARY(exp1 = e1, operator = op, exp2 = e2) := binaryExp;
  result := evalBinaryOp_dispatch(e1, op, e2, target);
end evalBinaryExp;

function evalBinaryOp_dispatch
  input Expression exp1;
  input Operator op;
  input Expression exp2;
  input EvalTarget target = noTarget;
  output Expression exp;
algorithm
  exp := match op.op
    case Op.ADD then evalBinaryAdd(exp1, exp2);
    case Op.SUB then evalBinarySub(exp1, exp2);
    case Op.MUL then evalBinaryMul(exp1, exp2);
    case Op.DIV then evalBinaryDiv(exp1, exp2, target);
    case Op.POW then evalBinaryPow(exp1, exp2, target);
    case Op.ADD_SCALAR_ARRAY then evalBinaryScalarArray(exp1, exp2, evalBinaryAdd);
    case Op.ADD_ARRAY_SCALAR then evalBinaryArrayScalar(exp1, exp2, evalBinaryAdd);
    case Op.SUB_SCALAR_ARRAY then evalBinaryScalarArray(exp1, exp2, evalBinarySub);
    case Op.SUB_ARRAY_SCALAR then evalBinaryArrayScalar(exp1, exp2, evalBinarySub);
    case Op.MUL_SCALAR_ARRAY then evalBinaryScalarArray(exp1, exp2, evalBinaryMul);
    case Op.MUL_ARRAY_SCALAR then evalBinaryArrayScalar(exp1, exp2, evalBinaryMul);
    case Op.MUL_VECTOR_MATRIX then evalBinaryMulVectorMatrix(exp1, exp2);
    case Op.MUL_MATRIX_VECTOR then evalBinaryMulMatrixVector(exp1, exp2);
    case Op.SCALAR_PRODUCT then evalBinaryScalarProduct(exp1, exp2);
    case Op.MATRIX_PRODUCT then evalBinaryMatrixProduct(exp1, exp2);
    case Op.DIV_SCALAR_ARRAY
      then evalBinaryScalarArray(exp1, exp2, function evalBinaryDiv(target = target));
    case Op.DIV_ARRAY_SCALAR
      then evalBinaryArrayScalar(exp1, exp2, function evalBinaryDiv(target = target));
    case Op.POW_SCALAR_ARRAY then evalBinaryScalarArray(exp1, exp2, function evalBinaryPow(target = target));
    case Op.POW_ARRAY_SCALAR then evalBinaryArrayScalar(exp1, exp2, function evalBinaryPow(target = target));
    case Op.POW_MATRIX then evalBinaryPowMatrix(exp1, exp2);
    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          Expression.toString(Expression.BINARY(exp1, op, exp2)), sourceInfo());
      then
        fail();
  end match;
end evalBinaryOp_dispatch;

function evalBinaryAdd
  input Expression exp1;
  input Expression exp2;
  output Expression exp;
algorithm
  exp := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then Expression.INTEGER(exp1.value + exp2.value);

    case (Expression.REAL(), Expression.REAL())
      then Expression.REAL(exp1.value + exp2.value);

    case (Expression.STRING(), Expression.STRING())
      then Expression.STRING(exp1.value + exp2.value);

    case (Expression.STRING(), Expression.FILENAME())
      then Expression.STRING(exp1.value + exp2.filename);

    case (Expression.FILENAME(), Expression.STRING())
      then Expression.STRING(exp1.filename + exp2.value);

    case (Expression.FILENAME(), Expression.FILENAME())
      then Expression.STRING(exp1.filename + exp2.filename);

    case (Expression.ARRAY(), Expression.ARRAY())
      guard arrayLength(exp1.elements) == arrayLength(exp2.elements)
      then Expression.makeArray(exp1.ty,
        Array.threadMap(exp1.elements, exp2.elements, evalBinaryAdd),
        literal = true);

    // technically the following two are incorrect because they need element wise addition
    // but the backend can create these and immediately tries to evaluate them.
    // kabdelhak: instead of fixing the operators we will just allow this to be immediately evaluated
    case (Expression.ARRAY(), Expression.INTEGER())
      then Expression.makeArray(exp1.ty,
        Array.map(exp1.elements, function evalBinaryAdd(exp2 = exp2)),
        literal = exp1.literal);
    case (Expression.INTEGER(), Expression.ARRAY())
      then Expression.makeArray(exp2.ty,
        Array.map(exp2.elements, function evalBinaryAdd(exp1 = exp1)),
        literal = exp2.literal);

    else
      algorithm
        exp := Expression.BINARY(exp1, Operator.makeAdd(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalBinaryAdd;

function evalBinarySub
  input Expression exp1;
  input Expression exp2;
  output Expression exp;
algorithm
  exp := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then Expression.INTEGER(exp1.value - exp2.value);

    case (Expression.REAL(), Expression.REAL())
      then Expression.REAL(exp1.value - exp2.value);

    case (Expression.ARRAY(), Expression.ARRAY())
      guard arrayLength(exp1.elements) == arrayLength(exp2.elements)
      then Expression.makeArray(exp1.ty,
        Array.threadMap(exp1.elements, exp2.elements, evalBinarySub),
        literal = true);

    else
      algorithm
        exp := Expression.BINARY(exp1, Operator.makeSub(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalBinarySub;

function evalBinaryMul
  input Expression exp1;
  input Expression exp2;
  output Expression exp;
algorithm
  exp := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then Expression.INTEGER(exp1.value * exp2.value);

    case (Expression.REAL(), Expression.REAL())
      then Expression.REAL(exp1.value * exp2.value);

    case (Expression.ARRAY(), Expression.ARRAY())
      guard arrayLength(exp1.elements) == arrayLength(exp2.elements)
      then Expression.makeArray(exp1.ty,
        Array.threadMap(exp1.elements, exp2.elements, evalBinaryMul),
        literal = true);

    else
      algorithm
        exp := Expression.BINARY(exp1, Operator.makeMul(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalBinaryMul;

function evalBinaryDiv
  input Expression exp1;
  input Expression exp2;
  input EvalTarget target;
  output Expression exp;
algorithm
  exp := match (exp1, exp2)
    case (_, Expression.REAL(0.0))
      algorithm
        if EvalTarget.hasInfo(target) then
          Error.addSourceMessage(Error.DIVISION_BY_ZERO,
            {Expression.toString(exp1), Expression.toString(exp2)}, EvalTarget.getInfo(target));
          fail();
        else
          exp := Expression.BINARY(exp1, Operator.makeDiv(Type.REAL()), exp2);
        end if;
      then
        exp;

    case (Expression.REAL(), Expression.REAL())
      then Expression.REAL(exp1.value / exp2.value);

    case (Expression.ARRAY(), Expression.ARRAY())
      guard arrayLength(exp1.elements) == arrayLength(exp2.elements)
      then Expression.makeArray(exp1.ty,
        Array.threadMap(exp1.elements, exp2.elements, function evalBinaryDiv(target = target)),
        literal = true);

    else
      algorithm
        exp := Expression.BINARY(exp1, Operator.makeDiv(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalBinaryDiv;

function evalBinaryPow
  input Expression exp1;
  input Expression exp2;
  input EvalTarget target;
  output Expression exp;
algorithm
  exp := match (exp1, exp2)
    case (Expression.REAL(), Expression.REAL())
      guard exp1.value < 0 and realInt(exp2.value) <> exp2.value
      algorithm
        if EvalTarget.hasInfo(target) then
          Error.addSourceMessage(Error.INVALID_NEGATIVE_POW,
            {Expression.toString(exp1), Expression.toString(exp2)}, EvalTarget.getInfo(target));
          fail();
        end if;
      then
        Expression.BINARY(exp1, Operator.makePow(Type.REAL()), exp2);

    case (Expression.REAL(), Expression.REAL())
      then Expression.REAL(exp1.value ^ exp2.value);

    case (Expression.ARRAY(), Expression.ARRAY())
      guard arrayLength(exp1.elements) == arrayLength(exp2.elements)
      then Expression.makeArray(exp1.ty,
        Array.threadMap(exp1.elements, exp2.elements, function evalBinaryPow(target = target)),
        literal = true);

    else
      algorithm
        exp := Expression.BINARY(exp1, Operator.makePow(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalBinaryPow;

function evalBinaryScalarArray
  input Expression scalarExp;
  input Expression arrayExp;
  input FuncT opFunc;
  output Expression exp;

  partial function FuncT
    input Expression exp1;
    input Expression exp2;
    output Expression exp;
  end FuncT;
algorithm
  exp := match arrayExp
    case Expression.ARRAY()
      then Expression.makeArray(arrayExp.ty,
        Array.map(arrayExp.elements, function evalBinaryScalarArray(scalarExp = scalarExp, opFunc = opFunc)),
        literal = true);

    else opFunc(scalarExp, arrayExp);
  end match;
end evalBinaryScalarArray;

function evalBinaryArrayScalar
  input Expression arrayExp;
  input Expression scalarExp;
  input FuncT opFunc;
  output Expression exp;

  partial function FuncT
    input Expression exp1;
    input Expression exp2;
    output Expression exp;
  end FuncT;
algorithm
  exp := match arrayExp
    case Expression.ARRAY()
      then Expression.makeArray(arrayExp.ty,
        Array.map(arrayExp.elements, function evalBinaryArrayScalar(scalarExp = scalarExp, opFunc = opFunc)),
        literal = true);

    else opFunc(arrayExp, scalarExp);
  end match;
end evalBinaryArrayScalar;

function evalBinaryMulVectorMatrix
  input Expression vectorExp;
  input Expression matrixExp;
  output Expression exp;
protected
  Dimension m;
  Type ty;
  array<Expression> arr;
algorithm
  exp := match Expression.transposeArray(matrixExp)
    case Expression.ARRAY(Type.ARRAY(ty, {m, _}), arr)
      algorithm
        arr := Array.map(arr, function evalBinaryScalarProduct(exp1 = vectorExp));
      then
        Expression.makeArray(Type.ARRAY(ty, {m}), arr, literal = true);

    else
      algorithm
        exp := Expression.BINARY(vectorExp, Operator.makeMul(Type.UNKNOWN()), matrixExp);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();

  end match;
end evalBinaryMulVectorMatrix;

function evalBinaryMulMatrixVector
  input Expression matrixExp;
  input Expression vectorExp;
  output Expression exp;
protected
  Dimension n;
  Type ty;
  array<Expression> arr;
algorithm
  exp := match matrixExp
    case Expression.ARRAY(Type.ARRAY(ty, {n, _}), arr)
      algorithm
        arr := Array.map(arr, function evalBinaryScalarProduct(exp2 = vectorExp));
      then
        Expression.makeArray(Type.ARRAY(ty, {n}), arr, literal = true);

    else
      algorithm
        exp := Expression.BINARY(matrixExp, Operator.makeMul(Type.UNKNOWN()), vectorExp);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();

  end match;
end evalBinaryMulMatrixVector;

function evalBinaryScalarProduct
  input Expression exp1;
  input Expression exp2;
  output Expression exp;
algorithm
  exp := match (exp1, exp2)
    local
      Type elem_ty;
      Expression e2;
      list<Expression> rest_e2;

    case (Expression.ARRAY(ty = Type.ARRAY(elem_ty)), Expression.ARRAY())
      guard arrayLength(exp1.elements) == arrayLength(exp2.elements)
      algorithm
        exp := Expression.makeZero(elem_ty);

        for i in 1:arrayLength(exp1.elements) loop
          exp := evalBinaryAdd(exp,
            evalBinaryMul(arrayGetNoBoundsChecking(exp1.elements, i),
                          arrayGetNoBoundsChecking(exp2.elements, i)));
        end for;
      then
        exp;

    else
      algorithm
        exp := Expression.BINARY(exp1, Operator.makeMul(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();

  end match;
end evalBinaryScalarProduct;

function evalBinaryMatrixProduct
  input Expression exp1;
  input Expression exp2;
  output Expression exp;
protected
  Expression e2;
  list<Expression> expl1, expl2;
  Type elem_ty, row_ty, mat_ty;
  Dimension n, p;
  array<Expression> arr1, arr2, arr;
algorithm
  e2 := Expression.transposeArray(exp2);

  exp := match (exp1, e2)
    case (Expression.ARRAY(Type.ARRAY(elem_ty, {n, _}), arr1),
          Expression.ARRAY(Type.ARRAY(_, {p, _}), arr2))
      algorithm
        mat_ty := Type.ARRAY(elem_ty, {n, p});

        if arrayEmpty(arr2) then
          exp := Expression.makeZero(mat_ty);
        else
          row_ty := Type.ARRAY(elem_ty, {p});
          arr := arrayCreateNoInit(arrayLength(arr1), exp1);

          for i in 1:arrayLength(arr1) loop
            arrayUpdateNoBoundsChecking(arr, i,
                Expression.makeArray(row_ty,
                  Array.map(arr2, function evalBinaryScalarProduct(exp1 = arrayGetNoBoundsChecking(arr1, i))),
                  literal = true));
          end for;

          exp := Expression.makeArray(mat_ty, arr, literal = true);
        end if;
      then
        exp;

    else
      algorithm
        exp := Expression.BINARY(exp1, Operator.makeMul(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();

  end match;
end evalBinaryMatrixProduct;

function evalBinaryPowMatrix
  input Expression matrixExp;
  input Expression nExp;
  output Expression exp;
protected
  Integer n;
algorithm
  exp := match nExp
    case Expression.INTEGER(value = 0)
      algorithm
        n := Dimension.size(listHead(Type.arrayDims(Expression.typeOf(matrixExp))));
      then
        Expression.makeIdentityMatrix(n, Type.REAL());

    case Expression.INTEGER(value = n)
      then evalBinaryPowMatrix2(matrixExp, n);

    else
      algorithm
        exp := Expression.BINARY(matrixExp, Operator.makePow(Type.UNKNOWN()), nExp);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();

  end match;
end evalBinaryPowMatrix;

function evalBinaryPowMatrix2
  input Expression matrix;
  input Integer n;
  output Expression exp;
algorithm
  exp := match n
    // A^1 = A
    case 1 then matrix;

    // A^2 = A * A
    case 2 then evalBinaryMatrixProduct(matrix, matrix);

    // A^n = A^m * A^m where n = 2*m
    case _ guard intMod(n, 2) == 0
      algorithm
        exp := evalBinaryPowMatrix2(matrix, intDiv(n, 2));
      then
        evalBinaryMatrixProduct(exp, exp);

    // A^n = A * A^(n-1)
    else
      algorithm
        exp := evalBinaryPowMatrix2(matrix, n - 1);
      then
        evalBinaryMatrixProduct(matrix, exp);

  end match;
end evalBinaryPowMatrix2;

function evalUnaryOp
  input Expression exp1;
  input Operator op;
  output Expression exp;
algorithm
  exp := match op.op
    case Op.UMINUS guard(Expression.isZero(exp1)) then exp1;
    case Op.UMINUS then Expression.mapSplitExpressions(exp1, evalUnaryMinus);
    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          Expression.toString(Expression.UNARY(op, exp1)), sourceInfo());
      then
        fail();
  end match;
end evalUnaryOp;

function evalUnaryMinus
  input Expression exp1;
  output Expression exp;
algorithm
  exp := match exp1
    case Expression.INTEGER() then Expression.INTEGER(-exp1.value);
    case Expression.REAL() then Expression.REAL(-exp1.value);

    case Expression.ARRAY()
      algorithm
        exp1.elements := Array.map(exp1.elements, evalUnaryMinus);
      then
        exp1;

    else
      algorithm
        exp := Expression.UNARY(Operator.makeUMinus(Type.UNKNOWN()), exp1);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalUnaryMinus;

function evalLogicBinaryOp
  input Expression exp1;
  input Operator op;
  input Expression exp2;
  input EvalTarget target = noTarget;
  output Expression exp;
algorithm
  exp := Expression.mapSplitExpressions(Expression.LBINARY(exp1, op, exp2),
    function evalLogicBinaryExp(target = target));
end evalLogicBinaryOp;

function evalLogicBinaryExp
  input Expression binaryExp;
  input EvalTarget target;
  output Expression result;
protected
  Expression e1, e2;
  Operator op;
algorithm
  Expression.LBINARY(exp1 = e1, operator = op, exp2 = e2) := binaryExp;
  result := evalLogicBinaryOp_dispatch(e1, op, e2, target);
end evalLogicBinaryExp;

function evalLogicBinaryOp_dispatch
  input Expression exp1;
  input Operator op;
  input Expression exp2;
  input EvalTarget target;
  output Expression exp;
algorithm
  exp := match op.op
    case Op.AND then evalLogicBinaryAnd(evalExp(exp1, target), exp2, target);
    case Op.OR then evalLogicBinaryOr(evalExp(exp1, target), exp2, target);
    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          Expression.toString(Expression.LBINARY(exp1, op, exp2)), sourceInfo());
      then
        fail();
  end match;
end evalLogicBinaryOp_dispatch;

function evalLogicBinaryAnd
  input Expression exp1;
  input Expression exp2;
  input EvalTarget target;
  output Expression exp;
algorithm
  exp := matchcontinue exp1
    local
      array<Expression> arr;

    case Expression.BOOLEAN()
      then if exp1.value then evalExp(exp2, target) else exp1;

    case Expression.ARRAY()
      algorithm
        Expression.ARRAY(elements = arr) := evalExp(exp2, target);
        arr := Array.threadMap(exp1.elements, arr, function evalLogicBinaryAnd(target = target));
      then
        Expression.makeArray(Type.setArrayElementType(exp1.ty, Type.BOOLEAN()), arr, literal = true);

    else
      algorithm
        exp := Expression.LBINARY(exp1, Operator.makeAnd(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end matchcontinue;
end evalLogicBinaryAnd;

function evalLogicBinaryOr
  input Expression exp1;
  input Expression exp2;
  input EvalTarget target;
  output Expression exp;
algorithm
  exp := match exp1
    local
      array<Expression> arr;

    case Expression.BOOLEAN()
      then if exp1.value then exp1 else evalExp(exp2, target);

    case Expression.ARRAY()
      algorithm
        Expression.ARRAY(elements = arr) := evalExp(exp2, target);
        arr := Array.threadMap(exp1.elements, arr, function evalLogicBinaryOr(target = target));
      then
        Expression.makeArray(Type.setArrayElementType(exp1.ty, Type.BOOLEAN()), arr, literal = true);

    else
      algorithm
        exp := Expression.LBINARY(exp1, Operator.makeOr(Type.UNKNOWN()), exp2);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalLogicBinaryOr;

function evalLogicUnaryOp
  input Expression exp1;
  input Operator op;
  output Expression exp;
algorithm
  exp := match op.op
    case Op.NOT then Expression.mapSplitExpressions(exp1, evalLogicUnaryNot);
    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          Expression.toString(Expression.LUNARY(op, exp1)), sourceInfo());
      then
        fail();
  end match;
end evalLogicUnaryOp;

function evalLogicUnaryNot
  input Expression exp1;
  output Expression exp;
algorithm
  exp := match exp1
    case Expression.BOOLEAN() then Expression.BOOLEAN(not exp1.value);
    case Expression.ARRAY() then Expression.mapArrayElements(exp1, evalLogicUnaryNot);

    else
      algorithm
        exp := Expression.LUNARY(Operator.makeNot(Type.UNKNOWN()), exp1);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
  end match;
end evalLogicUnaryNot;

function evalRelationOp
  input Expression exp1;
  input Operator op;
  input Expression exp2;
  output Expression exp;
algorithm
  exp := Expression.mapSplitExpressions(Expression.RELATION(exp1, op, exp2, -1), evalRelationExp);
end evalRelationOp;

function evalRelationExp
  input Expression relationExp;
  output Expression result;
protected
  Expression e1, e2;
  Operator op;
algorithm
  Expression.RELATION(exp1 = e1, operator = op, exp2 = e2) := relationExp;
  result := evalRelationOp_dispatch(e1, op, e2);
end evalRelationExp;

function evalRelationOp_dispatch
  input Expression exp1;
  input Operator op;
  input Expression exp2;
  output Expression exp;
protected
  Boolean res;
algorithm
  res := match op.op
    case Op.LESS then evalRelationLess(exp1, exp2);
    case Op.LESSEQ then evalRelationLessEq(exp1, exp2);
    case Op.GREATER then evalRelationGreater(exp1, exp2);
    case Op.GREATEREQ then evalRelationGreaterEq(exp1, exp2);
    case Op.EQUAL then evalRelationEqual(exp1, exp2);
    case Op.NEQUAL then evalRelationNotEqual(exp1, exp2);
    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          Expression.toString(Expression.RELATION(exp1, op, exp2, -1)), sourceInfo());
      then
        fail();
  end match;

  exp := Expression.BOOLEAN(res);
end evalRelationOp_dispatch;

function evalRelationLess
  input Expression exp1;
  input Expression exp2;
  output Boolean res;
algorithm
  res := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then exp1.value < exp2.value;
    case (Expression.REAL(), Expression.REAL())
      then exp1.value < exp2.value;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then exp1.value < exp2.value;
    case (Expression.STRING(), Expression.STRING())
      then stringCompare(exp1.value, exp2.value) < 0;
    case (Expression.STRING(), Expression.FILENAME())
      then stringCompare(exp1.value, exp2.filename) < 0;
    case (Expression.FILENAME(), Expression.STRING())
      then stringCompare(exp1.filename, exp2.value) < 0;
    case (Expression.FILENAME(), Expression.FILENAME())
      then stringCompare(exp1.filename, exp2.filename) < 0;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then exp1.index < exp2.index;

    else
      algorithm
        printFailedEvalError(getInstanceName(),
          Expression.RELATION(exp1, Operator.makeLess(Type.UNKNOWN()), exp2, -1), sourceInfo());
      then
        fail();
  end match;
end evalRelationLess;

function evalRelationLessEq
  input Expression exp1;
  input Expression exp2;
  output Boolean res;
algorithm
  res := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then exp1.value <= exp2.value;
    case (Expression.REAL(), Expression.REAL())
      then exp1.value <= exp2.value;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then exp1.value <= exp2.value;
    case (Expression.STRING(), Expression.STRING())
      then stringCompare(exp1.value, exp2.value) <= 0;
    case (Expression.STRING(), Expression.FILENAME())
      then stringCompare(exp1.value, exp2.filename) <= 0;
    case (Expression.FILENAME(), Expression.STRING())
      then stringCompare(exp1.filename, exp2.value) <= 0;
    case (Expression.FILENAME(), Expression.FILENAME())
      then stringCompare(exp1.filename, exp2.filename) <= 0;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then exp1.index <= exp2.index;

    else
      algorithm
        printFailedEvalError(getInstanceName(),
          Expression.RELATION(exp1, Operator.makeLessEq(Type.UNKNOWN()), exp2, -1), sourceInfo());
      then
        fail();
  end match;
end evalRelationLessEq;

function evalRelationGreater
  input Expression exp1;
  input Expression exp2;
  output Boolean res;
algorithm
  res := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then exp1.value > exp2.value;
    case (Expression.REAL(), Expression.REAL())
      then exp1.value > exp2.value;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then exp1.value > exp2.value;
    case (Expression.STRING(), Expression.STRING())
      then stringCompare(exp1.value, exp2.value) > 0;
    case (Expression.STRING(), Expression.FILENAME())
      then stringCompare(exp1.value, exp2.filename) > 0;
    case (Expression.FILENAME(), Expression.STRING())
      then stringCompare(exp1.filename, exp2.value) > 0;
    case (Expression.FILENAME(), Expression.FILENAME())
      then stringCompare(exp1.filename, exp2.filename) > 0;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then exp1.index > exp2.index;

    else
      algorithm
        printFailedEvalError(getInstanceName(),
          Expression.RELATION(exp1, Operator.makeGreater(Type.UNKNOWN()), exp2, -1), sourceInfo());
      then
        fail();
  end match;
end evalRelationGreater;

function evalRelationGreaterEq
  input Expression exp1;
  input Expression exp2;
  output Boolean res;
algorithm
  res := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then exp1.value >= exp2.value;
    case (Expression.REAL(), Expression.REAL())
      then exp1.value >= exp2.value;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then exp1.value >= exp2.value;
    case (Expression.STRING(), Expression.STRING())
      then stringCompare(exp1.value, exp2.value) >= 0;
    case (Expression.STRING(), Expression.FILENAME())
      then stringCompare(exp1.value, exp2.filename) >= 0;
    case (Expression.FILENAME(), Expression.STRING())
      then stringCompare(exp1.filename, exp2.value) >= 0;
    case (Expression.FILENAME(), Expression.FILENAME())
      then stringCompare(exp1.filename, exp2.filename) >= 0;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then exp1.index >= exp2.index;

    else
      algorithm
        printFailedEvalError(getInstanceName(),
          Expression.RELATION(exp1, Operator.makeGreaterEq(Type.UNKNOWN()), exp2, -1), sourceInfo());
      then
        fail();
  end match;
end evalRelationGreaterEq;

function evalRelationEqual
  input Expression exp1;
  input Expression exp2;
  output Boolean res;
algorithm
  res := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then exp1.value == exp2.value;
    case (Expression.REAL(), Expression.REAL())
      then exp1.value == exp2.value;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then exp1.value == exp2.value;
    case (Expression.STRING(), Expression.STRING())
      then stringCompare(exp1.value, exp2.value) == 0;
    case (Expression.STRING(), Expression.FILENAME())
      then stringCompare(exp1.value, exp2.filename) == 0;
    case (Expression.FILENAME(), Expression.STRING())
      then stringCompare(exp1.filename, exp2.value) == 0;
    case (Expression.FILENAME(), Expression.FILENAME())
      then stringCompare(exp1.filename, exp2.filename) == 0;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then exp1.index == exp2.index;

    else
      algorithm
        printFailedEvalError(getInstanceName(),
          Expression.RELATION(exp1, Operator.makeEqual(Type.UNKNOWN()), exp2, -1), sourceInfo());
      then
        fail();
  end match;
end evalRelationEqual;

function evalRelationNotEqual
  input Expression exp1;
  input Expression exp2;
  output Boolean res;
algorithm
  res := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then exp1.value <> exp2.value;
    case (Expression.REAL(), Expression.REAL())
      then exp1.value <> exp2.value;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then exp1.value <> exp2.value;
    case (Expression.STRING(), Expression.STRING())
      then stringCompare(exp1.value, exp2.value) <> 0;
    case (Expression.STRING(), Expression.FILENAME())
      then stringCompare(exp1.value, exp2.filename) <> 0;
    case (Expression.FILENAME(), Expression.STRING())
      then stringCompare(exp1.filename, exp2.value) <> 0;
    case (Expression.FILENAME(), Expression.FILENAME())
      then stringCompare(exp1.filename, exp2.filename) <> 0;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then exp1.index <> exp2.index;

    else
      algorithm
        printFailedEvalError(getInstanceName(),
          Expression.RELATION(exp1, Operator.makeNotEqual(Type.UNKNOWN()), exp2, -1), sourceInfo());
      then
        fail();
  end match;
end evalRelationNotEqual;

function evalIfExp
  input Expression ifExp;
  input EvalTarget target;
  output Expression result;
protected
  Type ty;
  Expression cond, btrue, bfalse;
algorithm
  Expression.IF(ty, cond, btrue, bfalse) := ifExp;
  result := Expression.IF(ty, evalExp(cond, target), btrue, bfalse);
  result := Expression.mapSplitExpressions(result, function evalIfExp2(target = target));
end evalIfExp;

function evalIfExp2
  input Expression ifExp;
  input EvalTarget target;
  output Expression result;
protected
  Type ty;
  Expression cond, tb, fb;
algorithm
  Expression.IF(ty = ty, condition = cond, trueBranch = tb, falseBranch = fb) := ifExp;

  result := match cond
    case Expression.BOOLEAN()
      algorithm
        if Type.isConditionalArray(ty) and not Type.isMatchedBranch(cond.value, ty) then
          (tb, fb) := Util.swap(cond.value, fb, tb);
          Error.addSourceMessage(Error.ARRAY_DIMENSION_MISMATCH,
            {Expression.toString(tb), Type.toString(Expression.typeOf(tb)),
             Dimension.toStringList(Type.arrayDims(Expression.typeOf(fb)), brackets = false)},
             EvalTarget.getInfo(target));
          fail();
        end if;
      then
        evalExp(if cond.value then tb else fb, target);

    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          Expression.toString(ifExp), sourceInfo());
      then
        fail();
  end match;
end evalIfExp2;

function evalCast
  input Expression castExp;
  input Type castTy;
  output Expression exp;
algorithm
  exp := Expression.typeCast(castExp, castTy);

  // Expression.typeCast will just create a CAST if it can't typecast
  // the expression, so make sure we actually got something else back.
  () := match exp
    case Expression.CAST()
      algorithm
        exp := Expression.CAST(castTy, castExp);
        printFailedEvalError(getInstanceName(), exp, sourceInfo());
      then
        fail();
    else ();
  end match;
end evalCast;

function evalCall
  input Call call;
  input EvalTarget target;
  output Expression exp;
protected
  Call c = call;
algorithm
  exp := match c
    local
      list<Expression> args;

    case Call.TYPED_CALL()
      algorithm
        c.arguments := list(evalExp(arg, target) for arg in c.arguments);
      then
        if Function.isBuiltin(c.fn) then
          Expression.mapSplitExpressions(Expression.CALL(c), function evalBuiltinCallExp(target = target))
        else
          Expression.mapSplitExpressions(Expression.CALL(c), function evalNormalCallExp(target = target));

    case Call.TYPED_ARRAY_CONSTRUCTOR()
      algorithm
        c.exp := evalExpPartial(c.exp);
        c.iters := Call.mapIteratorsExpShallow(c.iters, evalExpPartialDefault);
      then
        Expression.mapSplitExpressions(Expression.CALL(c), evalArrayConstructor);

    case Call.TYPED_REDUCTION()
      algorithm
        c.exp := evalExpPartial(c.exp);
        c.iters := Call.mapIteratorsExpShallow(c.iters, evalExpPartialDefault);
      then
        Expression.mapSplitExpressions(Expression.CALL(c), evalReduction);

    else
      algorithm
        Error.addInternalError(getInstanceName() + " got untyped call", sourceInfo());
      then
        fail();

  end match;
end evalCall;

function evalBuiltinCallExp
  input Expression callExp;
  input EvalTarget target;
  output Expression result;
protected
  Function fn;
  list<Expression> args;
algorithm
  Expression.CALL(call = Call.TYPED_CALL(fn = fn, arguments = args)) := callExp;
  result := evalBuiltinCall(fn, args, target);
end evalBuiltinCallExp;

function evalBuiltinCall
  input Function fn;
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Absyn.Path fn_path = Function.nameConsiderBuiltin(fn);
algorithm
  result := match AbsynUtil.pathFirstIdent(fn_path)
    case "abs" then evalBuiltinAbs(listHead(args));
    case "acos" then evalBuiltinAcos(listHead(args), target);
    case "array" then evalBuiltinArray(args);
    case "asin" then evalBuiltinAsin(listHead(args), target);
    case "atan2" then evalBuiltinAtan2(args);
    case "atan" then evalBuiltinAtan(listHead(args));
    case "cat" then evalBuiltinCat(listHead(args), listRest(args), target);
    case "ceil" then evalBuiltinCeil(listHead(args));
    case "cosh" then evalBuiltinCosh(listHead(args));
    case "cos" then evalBuiltinCos(listHead(args));
    case "der" then evalBuiltinDer(listHead(args));
    // TODO: Fix typing of diagonal so the argument isn't boxed.
    case "diagonal" then evalBuiltinDiagonal(Expression.unbox(listHead(args)));
    case "div" then evalBuiltinDiv(args, target);
    case "exp" then evalBuiltinExp(listHead(args));
    case "fill" then evalBuiltinFill(args);
    case "floor" then evalBuiltinFloor(listHead(args));
    case "identity" then evalBuiltinIdentity(listHead(args));
    case "integer" then evalBuiltinInteger(listHead(args));
    case "Integer" then evalBuiltinIntegerEnum(listHead(args));
    case "log10" then evalBuiltinLog10(listHead(args), target);
    case "log" then evalBuiltinLog(listHead(args), target);
    case "matrix" then evalBuiltinMatrix(listHead(args));
    case "max" then evalBuiltinMax(args, fn);
    case "min" then evalBuiltinMin(args, fn);
    case "mod" then evalBuiltinMod(args, target);
    case "noEvent" then listHead(args); // No events during ceval, just return the argument.
    case "ones" then evalBuiltinOnes(args);
    case "pre" then listHead(args);
    case "product" then evalBuiltinProduct(listHead(args));
    case "promote" then evalBuiltinPromote(listGet(args,1),listGet(args,2));
    case "rem" then evalBuiltinRem(args, target);
    case "scalar" then evalBuiltinScalar(listHead(args));
    case "sign" then evalBuiltinSign(listHead(args));
    case "sinh" then evalBuiltinSinh(listHead(args));
    case "sin" then evalBuiltinSin(listHead(args));
    case "skew" then evalBuiltinSkew(listHead(args));
    case "smooth" then listGet(args, 2);
    case "sqrt" then evalBuiltinSqrt(listHead(args));
    case "String" then evalBuiltinString(args);
    case "sum" then evalBuiltinSum(listHead(args));
    case "symmetric" then evalBuiltinSymmetric(listHead(args));
    case "tanh" then evalBuiltinTanh(listHead(args));
    case "tan" then evalBuiltinTan(listHead(args));
    case "transpose" then evalBuiltinTranspose(listHead(args));
    case "vector" then evalBuiltinVector(listHead(args));
    case "zeros" then evalBuiltinZeros(args);
    case "OpenModelica_uriToFilename" then evalUriToFilename(fn, listHead(args), target);
    case "intBitAnd" then evalIntBitAnd(args);
    case "intBitOr" then evalIntBitOr(args);
    case "intBitXor" then evalIntBitXor(args);
    case "intBitLShift" then evalIntBitLShift(args);
    case "intBitRShift" then evalIntBitRShift(args);
    case "intMaxLit" then Expression.INTEGER(System.intMaxLit());
    case "inferredClock" then evalInferredClock(args);
    case "rationalClock" then evalRationalClock(args);
    case "realClock" then evalRealClock(args);
    case "booleanClock" then evalBooleanClock(args);
    case "solverClock" then evalSolverClock(args);
    case "getInstanceName" then evalGetInstanceName(listHead(args));
    case "$OMC$PositiveMax" then evalPositiveMax(listGet(args,1),listGet(args,2));
    case "$OMC$inStreamDiv" then listHead(args);
    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          AbsynUtil.pathString(fn_path), sourceInfo());
      then
        fail();
  end match;
end evalBuiltinCall;

function evalNormalCallExp
  input Expression callExp;
  input EvalTarget target;
  output Expression result;
protected
  Function fn;
  list<Expression> args;
algorithm
  Expression.CALL(call = Call.TYPED_CALL(fn = fn, arguments = args)) := callExp;
  result := evalNormalCall(fn, args, target);
end evalNormalCallExp;

function evalNormalCall
  input Function fn;
  input list<Expression> args;
  input EvalTarget target;
  output Expression result = EvalFunction.evaluate(fn, args, target);
end evalNormalCall;

function evalBuiltinAbs
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.INTEGER() then Expression.INTEGER(abs(arg.value));
    case Expression.REAL() then Expression.REAL(abs(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAbs;

function evalBuiltinAcos
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x < -1.0 or x > 1.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "acos", "-1 <= x <= 1"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(acos(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAcos;

function evalBuiltinArray
  input list<Expression> args;
  output Expression result;
protected
  Type ty;
algorithm
  ty := Expression.typeOf(listHead(args));
  ty := Type.liftArrayLeft(ty, Dimension.fromInteger(listLength(args)));
  result := Expression.makeArray(ty, listArray(args), literal = true);
end evalBuiltinArray;

function evalBuiltinAsin
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x < -1.0 or x > 1.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "asin", "-1 <= x <= 1"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(asin(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAsin;

function evalBuiltinAtan2
  input list<Expression> args;
  output Expression result;
protected
  Real y, x;
algorithm
  result := match args
    case {Expression.REAL(value = y), Expression.REAL(value = x)}
      then Expression.REAL(atan2(y, x));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinAtan2;

function evalBuiltinAtan
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(atan(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAtan;

function evalBuiltinCat
  input Expression argN;
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Integer n, nd, sz;
  Type ty;
  list<Expression> es;
  list<Integer> dims;
algorithm
  Expression.INTEGER(n) := argN;
  ty := Expression.typeOf(listHead(args));
  nd := Type.dimensionCount(ty);

  if n > nd or n < 1 then
    if EvalTarget.hasInfo(target) then
      Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE, {String(n), "cat", "1 <= x <= " + String(nd)}, EvalTarget.getInfo(target));
    end if;
    fail();
  end if;

  es := list(e for e guard not Expression.isEmptyArray(e) in args);
  sz := listLength(es);

  if sz == 0 then
    result := listHead(args);
  elseif sz == 1 then
    result := listHead(es);
  else
    (es,dims) := ExpressionSimplify.evalCat(n, es, getArrayContents=Expression.arrayElementList, toString=Expression.toString);
    result := Expression.arrayFromList(es, Expression.typeOf(listHead(es)), list(Dimension.fromInteger(d) for d in dims));
  end if;
end evalBuiltinCat;

function evalBuiltinCeil
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(ceil(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinCeil;

function evalBuiltinCosh
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(cosh(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinCosh;

function evalBuiltinCos
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(cos(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinCos;

function evalBuiltinDer
  input Expression arg;
  output Expression result;
algorithm
  result := Expression.fillType(Expression.typeOf(arg), Expression.REAL(0.0));
end evalBuiltinDer;

function evalBuiltinDiagonal
  input Expression arg;
  output Expression result;
protected
  Type elem_ty, row_ty;
  Expression zero, exp;
  list<Expression> elems, row, rows = {};
  Integer n, i = 1;
  Boolean e_lit, arg_lit = true;
  array<Expression> arr_zero, arr_row, arr_rows;
algorithm
  result := match arg
    case Expression.ARRAY() guard arrayEmpty(arg.elements) then arg;

    case Expression.ARRAY()
      algorithm
        n := arrayLength(arg.elements);
        elem_ty := Type.unliftArray(arg.ty);
        row_ty := Type.liftArrayLeft(elem_ty, Dimension.fromInteger(n));
        zero := Expression.makeZero(elem_ty);
        arr_zero := arrayCreate(n, zero);
        arr_rows := arrayCreateNoInit(n, zero);

        for i in 1:n loop
          arr_row := arrayCopy(arr_zero);
          exp := arrayGetNoBoundsChecking(arg.elements, i);
          e_lit := Expression.isLiteral(exp);
          arg_lit := arg_lit and e_lit;
          arrayUpdateNoBoundsChecking(arr_row, i, exp);
          exp := Expression.makeArray(row_ty, arr_row, e_lit);
          arrayUpdateNoBoundsChecking(arr_rows, i, exp);
        end for;
      then
        Expression.makeArray(Type.liftArrayLeft(row_ty, Dimension.fromInteger(n)), arr_rows, arg_lit);

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinDiagonal;

function evalBuiltinDiv
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Real rx, ry;
  Integer ix, iy;
algorithm
  result := match args
    case {Expression.INTEGER(ix), Expression.INTEGER(iy)}
      algorithm
        if iy == 0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.DIVISION_BY_ZERO,
              {String(ix), String(iy)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.INTEGER(intDiv(ix, iy));

    case {Expression.REAL(rx), Expression.REAL(ry)}
      algorithm
        if ry == 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.DIVISION_BY_ZERO,
              {String(rx), String(ry)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;

        rx := rx / ry;
      then
        Expression.REAL(if rx < 0.0 then ceil(rx) else floor(rx));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinDiv;

function evalBuiltinExp
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(exp(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinExp;

public
function evalBuiltinFill
  input list<Expression> args;
  output Expression result;
protected
  Expression fill_exp;
  list<Expression> dims;
algorithm
  try
    fill_exp :: dims := args;
    result := Expression.fillArgs(fill_exp, dims);
  else
    printWrongArgsError(getInstanceName(), args, sourceInfo());
    fail();
  end try;
end evalBuiltinFill;

protected
function evalBuiltinFloor
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(floor(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinFloor;

function evalBuiltinIdentity
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.INTEGER()
      then Expression.makeIdentityMatrix(arg.value, Type.INTEGER());

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinIdentity;

function evalBuiltinInteger
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.INTEGER() then arg;
    case Expression.REAL() then Expression.INTEGER(realInt(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinInteger;

function evalBuiltinIntegerEnum
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.ENUM_LITERAL() then Expression.INTEGER(arg.index);
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinIntegerEnum;

function evalBuiltinLog10
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x <= 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "log10", "x > 0"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(log10(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinLog10;

function evalBuiltinLog
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x <= 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "log", "x > 0"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(log(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinLog;

function evalBuiltinMatrix
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    local
      Integer dim_count;
      Dimension dim1, dim2;
      Type ty;
      array<Expression> arr;

    case Expression.ARRAY(ty = ty)
      algorithm
        dim_count := Type.dimensionCount(ty);

        if dim_count < 2 then
          result := Expression.promote(arg, ty, 2);
        elseif dim_count == 2 then
          result := arg;
        else
          dim1 :: dim2 :: _ := Type.arrayDims(ty);
          ty := Type.liftArrayLeft(Type.arrayElementType(ty), dim2);
          arr := Array.map(arg.elements, function evalBuiltinMatrix2(ty = ty));
          ty := Type.liftArrayLeft(ty, dim1);
          result := Expression.makeArray(ty, arr);
        end if;
      then
        result;

    else
      algorithm
        ty := Expression.typeOf(arg);

        if Type.isScalar(ty) then
          result := Expression.promote(arg, ty, 2);
        else
          printWrongArgsError(getInstanceName(), {arg}, sourceInfo());
          fail();
        end if;
      then
        result;

  end match;
end evalBuiltinMatrix;

function evalBuiltinMatrix2
  input Expression arg;
  input Type ty;
  output Expression result;
algorithm
  result := match arg
    case Expression.ARRAY()
      then Expression.makeArray(ty,
                                Array.map(arg.elements, Expression.toScalar),
                                arg.literal);

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinMatrix2;

function evalBuiltinMax
  input list<Expression> args;
  input Function fn;
  output Expression result;
protected
  Expression e1, e2;
  Type ty;
algorithm
  result := match args
    case {e1, e2} then evalBuiltinMax2(e1, e2);

    case {e1}
      guard Expression.isArray(e1)
      algorithm
        ty := Expression.typeOf(e1);
        result := Expression.fold(e1, evalBuiltinMax2, Expression.EMPTY(ty));

        if Expression.isEmpty(result) then
          result := Expression.makeMinValue(Type.arrayElementType(ty));
        end if;
      then
        result;

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinMax;

function evalBuiltinMax2
  input Expression exp1;
  input Expression exp2;
  output Expression result;
algorithm
  result := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then if exp1.value < exp2.value then exp2 else exp1;
    case (Expression.REAL(), Expression.REAL())
      then if exp1.value < exp2.value then exp2 else exp1;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then if exp1.value < exp2.value then exp2 else exp1;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then if exp1.index < exp2.index then exp2 else exp1;
    case (Expression.ARRAY(), _) then exp2;
    case (_, Expression.EMPTY()) then exp1;
    else algorithm printWrongArgsError(getInstanceName(), {exp1, exp2}, sourceInfo()); then fail();
  end match;
end evalBuiltinMax2;

function evalPositiveMax
  input Expression flow_exp;
  input Expression eps;
  output Expression result;
algorithm
  result := if Expression.isNonPositive(flow_exp)
    then Expression.makeZero(Expression.typeOf(flow_exp))
    else evalBuiltinMax2(flow_exp, eps);
end evalPositiveMax;

function evalBuiltinMin
  input list<Expression> args;
  input Function fn;
  output Expression result;
protected
  Expression e1, e2;
  Type ty;
algorithm
  result := match args
    case {e1, e2} then evalBuiltinMin2(e1, e2);

    case {e1}
      guard Expression.isArray(e1)
      algorithm
        ty := Expression.typeOf(e1);
        result := Expression.fold(e1, evalBuiltinMin2, Expression.EMPTY(ty));

        if Expression.isEmpty(result) then
          result := Expression.makeMaxValue(Type.arrayElementType(ty));
        end if;
      then
        result;

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinMin;

function evalBuiltinMin2
  input Expression exp1;
  input Expression exp2;
  output Expression result;
algorithm
  result := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then if exp1.value > exp2.value then exp2 else exp1;
    case (Expression.REAL(), Expression.REAL())
      then if exp1.value > exp2.value then exp2 else exp1;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then if exp1.value > exp2.value then exp2 else exp1;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then if exp1.index > exp2.index then exp2 else exp1;
    case (Expression.ARRAY(), _) then exp2;
    case (_, Expression.EMPTY()) then exp1;
    else algorithm printWrongArgsError(getInstanceName(), {exp1, exp2}, sourceInfo()); then fail();
  end match;
end evalBuiltinMin2;

function evalBuiltinMod
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Expression x, y;
algorithm
  {x, y} := args;

  result := match (x, y)
    case (Expression.INTEGER(), Expression.INTEGER())
      algorithm
        if y.value == 0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.MODULO_BY_ZERO,
              {String(x.value), String(y.value)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.INTEGER(mod(x.value, y.value));

    case (Expression.REAL(), Expression.REAL())
      algorithm
        if y.value == 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.MODULO_BY_ZERO,
              {String(x.value), String(y.value)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(mod(x.value, y.value));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinMod;

function evalBuiltinOnes
  input list<Expression> args;
  output Expression result;
algorithm
  result := evalBuiltinFill(Expression.INTEGER(1) :: args);
end evalBuiltinOnes;

function evalBuiltinProduct
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case _
      guard Expression.isArray(arg)
      then match Type.arrayElementType(Expression.typeOf(arg))
        case Type.INTEGER() then Expression.INTEGER(Expression.fold(arg, evalBuiltinProductInt, 1));
        case Type.REAL() then Expression.REAL(Expression.fold(arg, evalBuiltinProductReal, 1.0));
        else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
      end match;

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinProduct;

function evalBuiltinProductInt
  input Expression exp;
  input output Integer result;
algorithm
  result := match exp
    case Expression.INTEGER() then result * exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinProductInt;

function evalBuiltinProductReal
  input Expression exp;
  input output Real result;
algorithm
  result := match exp
    case Expression.REAL() then result * exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinProductReal;

function evalBuiltinPromote
  input Expression arg, argN;
  output Expression result;
protected
  Integer n;
algorithm
  if Expression.isInteger(argN) then
    Expression.INTEGER(n) := argN;
    result := Expression.promote(arg, Expression.typeOf(arg), n);
  else
    printWrongArgsError(getInstanceName(), {arg, argN}, sourceInfo());
    fail();
  end if;
end evalBuiltinPromote;

function evalBuiltinRem
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Expression x, y;
algorithm
  {x, y} := args;

  result := match (x, y)
    case (Expression.INTEGER(), Expression.INTEGER())
      algorithm
        if y.value == 0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.REM_ARG_ZERO, {String(x.value),
                String(y.value)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.INTEGER(x.value - (div(x.value, y.value) * y.value));

    case (Expression.REAL(), Expression.REAL())
      algorithm
        if y.value == 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.REM_ARG_ZERO,
              {String(x.value), String(y.value)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(x.value - (div(x.value, y.value) * y.value));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinRem;

function evalBuiltinScalar
  input Expression arg;
  output Expression result = arg;
algorithm
  while Expression.isArray(result) loop
    result := Expression.arrayScalarElement(result);
  end while;
end evalBuiltinScalar;

function evalBuiltinSign
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL()
      then Expression.INTEGER(if arg.value > 0 then 1 else if arg.value < 0 then -1 else 0);
    case Expression.INTEGER()
      then Expression.INTEGER(if arg.value > 0 then 1 else if arg.value < 0 then -1 else 0);
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSign;

function evalBuiltinSinh
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(sinh(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSinh;

function evalBuiltinSin
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(sin(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSin;

function evalBuiltinSkew
  input Expression arg;
  output Expression result;
protected
  Expression x1, x2, x3, y1, y2, y3;
  Type ty;
  Expression zero;
  Boolean literal;
algorithm
  result := match arg
    case Expression.ARRAY(ty = ty, literal = literal)
      algorithm
        x1 := arrayGet(arg.elements, 1);
        x2 := arrayGet(arg.elements, 2);
        x3 := arrayGet(arg.elements, 3);
        zero := Expression.makeZero(Type.arrayElementType(ty));
        y1 := Expression.makeArray(ty, listArray({zero, Expression.negate(x3), x2}), literal);
        y2 := Expression.makeArray(ty, listArray({x3, zero, Expression.negate(x1)}), literal);
        y3 := Expression.makeArray(ty, listArray({Expression.negate(x2), x1, zero}), literal);
        ty := Type.liftArrayLeft(ty, Dimension.fromInteger(3));
      then
        Expression.makeArray(ty, listArray({y1, y2, y3}), literal);

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSkew;

function evalBuiltinSqrt
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(sqrt(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSqrt;

function evalBuiltinString
  input list<Expression> args;
  output Expression result;
algorithm
  result := match args
    local
      Expression arg;
      Integer min_len, str_len, significant_digits, idx, c;
      Boolean left_justified;
      String str, format;
      Real r;

    case {arg, Expression.INTEGER(min_len), Expression.BOOLEAN(left_justified)}
      algorithm
        str := match arg
          case Expression.INTEGER() then intString(arg.value);
          case Expression.BOOLEAN() then boolString(arg.value);
          case Expression.ENUM_LITERAL() then arg.name;
          else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
        end match;

        str_len := stringLength(str);
        if str_len < min_len then
          if left_justified then
            str := str + stringAppendList(List.fill(" ", min_len - str_len));
          else
            str := stringAppendList(List.fill(" ", min_len - str_len)) + str;
          end if;
        end if;
      then
        Expression.STRING(str);

    case {Expression.REAL(r), Expression.INTEGER(significant_digits),
          Expression.INTEGER(min_len), Expression.BOOLEAN(left_justified)}
      algorithm
        format := "%" + (if left_justified then "-" else "") +
                  intString(min_len) + "." + intString(significant_digits) + "g";
        str := System.sprintff(format, r);
      then
        Expression.STRING(str);

    case {Expression.REAL(r), Expression.STRING(format)}
      algorithm
        str := System.sprintff("%" + format, r);
      then
        Expression.STRING(str);

  end match;
end evalBuiltinString;

function evalBuiltinSum
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case _ guard Expression.isArray(arg)
      then match Type.arrayElementType(Expression.typeOf(arg))
        case Type.INTEGER() then Expression.INTEGER(Expression.fold(arg, evalBuiltinSumInt, 0));
        case Type.REAL() then Expression.REAL(Expression.fold(arg, evalBuiltinSumReal, 0.0));
        else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
      end match;

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSum;

function evalBuiltinSumInt
  input Expression exp;
  input output Integer result;
algorithm
  result := match exp
    case Expression.INTEGER() then result + exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinSumInt;

function evalBuiltinSumReal
  input Expression exp;
  input output Real result;
algorithm
  result := match exp
    case Expression.REAL() then result + exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinSumReal;

function evalBuiltinSymmetric
  input Expression arg;
  output Expression result;
protected
  array<array<Expression>> mat;
  Integer n;
  Type ty, row_ty;
  array<Expression> arr, accum;
algorithm
  ty := Expression.typeOf(arg);

  if Expression.isArray(arg) and Type.isSquareMatrix(ty) then
    mat := Array.map(Expression.arrayElements(arg), Expression.arrayElements);
    n := arrayLength(mat);
    row_ty := Type.unliftArray(Expression.typeOf(arg));
    accum := arrayCreateNoInit(n, arg);

    for i in 1:n loop
      arr := arrayCreateNoInit(n, arg);

      for j in 1:n loop
        arrayUpdateNoBoundsChecking(arr, j,
          if i > j then arrayGet(mat[j], i) else arrayGet(mat[i], j));
      end for;

      arrayUpdateNoBoundsChecking(accum, i,
        Expression.makeArray(row_ty, arr, literal = true));
    end for;

    result := Expression.makeArray(ty, accum, literal = true);
  else
    printWrongArgsError(getInstanceName(), {arg}, sourceInfo());
    fail();
  end if;
end evalBuiltinSymmetric;

function evalBuiltinTanh
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(tanh(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinTanh;

function evalBuiltinTan
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(tan(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinTan;

function evalBuiltinTranspose
  input Expression arg;
  output Expression result;
protected
  Dimension dim1, dim2;
  list<Dimension> rest_dims;
  Type ty;
  list<Expression> arr;
  list<list<Expression>> arrl;
  Boolean literal;
algorithm
  ty := Expression.typeOf(arg);

  if Expression.isArray(arg) and Type.dimensionCount(ty) >= 2 then
    result := Expression.transposeArray(arg);
  else
    printWrongArgsError(getInstanceName(), {arg}, sourceInfo());
    fail();
  end if;
end evalBuiltinTranspose;

function evalBuiltinVector
  input Expression arg;
  output Expression result;
protected
  list<Expression> expl;
  Type ty;
algorithm
  expl := Expression.arrayScalarElements(arg);
  result := Expression.makeExpArray(listArray(expl),
    Type.arrayElementType(Expression.typeOf(arg)), isLiteral = true);
end evalBuiltinVector;

function evalBuiltinZeros
  input list<Expression> args;
  output Expression result;
algorithm
  result := evalBuiltinFill(Expression.INTEGER(0) :: args);
end evalBuiltinZeros;

function evalUriToFilename
  input Function fn;
  input Expression arg;
  input EvalTarget target;
  output Expression result;
algorithm
  result := match arg
    case Expression.STRING()
      then Expression.FILENAME(OpenModelica.Scripting.uriToFilename(arg.value));

    case Expression.FILENAME()
      then Expression.FILENAME(OpenModelica.Scripting.uriToFilename(arg.filename));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalUriToFilename;

function evalIntBitAnd
  input list<Expression> args;
  output Expression result;
protected
  Integer i1, i2;
algorithm
  result := match args
    case {Expression.INTEGER(value = i1), Expression.INTEGER(value = i2)}
      then Expression.INTEGER(intBitAnd(i1, i2));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalIntBitAnd;

function evalIntBitOr
  input list<Expression> args;
  output Expression result;
protected
  Integer i1, i2;
algorithm
  result := match args
    case {Expression.INTEGER(value = i1), Expression.INTEGER(value = i2)}
      then Expression.INTEGER(intBitOr(i1, i2));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalIntBitOr;

function evalIntBitXor
  input list<Expression> args;
  output Expression result;
protected
  Integer i1, i2;
algorithm
  result := match args
    case {Expression.INTEGER(value = i1), Expression.INTEGER(value = i2)}
      then Expression.INTEGER(intBitXor(i1, i2));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalIntBitXor;

function evalIntBitLShift
  input list<Expression> args;
  output Expression result;
protected
  Integer i1, i2;
algorithm
  result := match args
    case {Expression.INTEGER(value = i1), Expression.INTEGER(value = i2)}
      then Expression.INTEGER(intBitLShift(i1, i2));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalIntBitLShift;

function evalIntBitRShift
  input list<Expression> args;
  output Expression result;
protected
  Integer i1, i2;
algorithm
  result := match args
    case {Expression.INTEGER(value = i1), Expression.INTEGER(value = i2)}
      then Expression.INTEGER(intBitRShift(i1, i2));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalIntBitRShift;

function evalInferredClock
  input list<Expression> args;
  output Expression result;
algorithm
  result := match args
    case {}
      then Expression.CLKCONST(Expression.ClockKind.INFERRED_CLOCK());

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalInferredClock;

function evalRationalClock
  input list<Expression> args;
  output Expression result;
algorithm
  result := match args
    local
      Expression interval, resolution;

    case {interval as Expression.INTEGER(), resolution as Expression.INTEGER()}
      then Expression.CLKCONST(Expression.ClockKind.RATIONAL_CLOCK(interval, resolution));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalRationalClock;

function evalRealClock
  input list<Expression> args;
  output Expression result;
algorithm
  result := match args
    local
      Expression interval;

    case {interval as Expression.REAL()}
      then Expression.CLKCONST(Expression.ClockKind.REAL_CLOCK(interval));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalRealClock;

function evalBooleanClock
  input list<Expression> args;
  output Expression result;
algorithm
  result := match args
    local
      Expression condition, interval;

    case {condition as Expression.BOOLEAN(), interval as Expression.REAL()}
      then Expression.CLKCONST(Expression.ClockKind.EVENT_CLOCK(condition, interval));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBooleanClock;

function evalSolverClock
  input list<Expression> args;
  output Expression result;
algorithm
  result := match args
    local
      Expression c, solver;

    case {c as Expression.CLKCONST(), solver as Expression.STRING()}
      then Expression.CLKCONST(Expression.ClockKind.SOLVER_CLOCK(c, solver));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalSolverClock;

public function evalGetInstanceName
  input Expression scopeArg;
  output Expression result;
protected
  ComponentRef cref;
algorithm
  // getInstanceName is normally evaluated by the flattening, but we might get
  // here when getInstanceName is used in e.g. a package. In that case use the
  // scope that was added as an argument during the typing.
  cref := Expression.toCref(scopeArg);
  result := Expression.STRING(AbsynUtil.pathString(InstNode.rootPath(ComponentRef.node(cref))));
end evalGetInstanceName;

protected function evalArrayConstructor
  input Expression callExp;
  output Expression result;
protected
  Expression exp;
  list<tuple<InstNode, Expression>> iters;
  list<Mutable<Expression>> iter_exps;
  list<Expression> ranges;
algorithm
  Expression.CALL(call = Call.TYPED_ARRAY_CONSTRUCTOR(exp = exp, iters = iters)) := callExp;
  (exp, ranges, iter_exps) := Expression.createIterationRanges(exp, iters);
  result := evalArrayConstructor2(exp, ranges, iter_exps);
end evalArrayConstructor;

function evalArrayConstructor2
  input Expression exp;
  input list<Expression> ranges;
  input list<Mutable<Expression>> iterators;
  output Expression result;
protected
  Expression range, e;
  list<Expression> ranges_rest, expl = {};
  array<Expression> arr;
  Mutable<Expression> iter;
  list<Mutable<Expression>> iters_rest;
  ExpressionIterator range_iter;
  Expression value;
  Type ty;
algorithm
  if listEmpty(ranges) then
    result := evalExp(exp);
  else
    range :: ranges_rest := ranges;
    range := evalExp(range);
    iter :: iters_rest := iterators;
    range_iter := ExpressionIterator.fromExp(range);

    while ExpressionIterator.hasNext(range_iter) loop
      (range_iter, value) := ExpressionIterator.next(range_iter);
      Mutable.update(iter, value);
      expl := evalArrayConstructor2(exp, ranges_rest, iters_rest) :: expl;
    end while;

    arr := listArray(listReverseInPlace(expl));

    ty := if arrayEmpty(arr) then
      Type.liftArrayLeftList(Expression.typeOf(exp), List.mapFlat(ranges_rest, Expression.dimensions)) else
      Expression.typeOf(listHead(expl));

    ty := Type.liftArrayLeft(ty, Dimension.fromInteger(arrayLength(arr)));
    result := Expression.makeArray(ty, arr, literal = true);
  end if;
end evalArrayConstructor2;

partial function ReductionFn
  input Expression exp1;
  input Expression exp2;
  output Expression result;
end ReductionFn;

function evalReduction
  input Expression callExp;
  output Expression result;
protected
  Function fn;
  Expression exp, default_exp;
  list<tuple<InstNode, Expression>> iters;
  Type ty;
  ReductionFn red_fn;

  function reductionFn
    input Expression exp1;
    input Expression exp2;
    input EvalTarget target;
    input ReductionFn fn;
    output Expression result = fn(exp1, evalExp(exp2, target));
  end reductionFn;
algorithm
  Expression.CALL(call = Call.TYPED_REDUCTION(fn = fn, exp = exp, iters = iters)) := callExp;
  ty := Expression.typeOf(exp);

  (red_fn, default_exp) := match AbsynUtil.pathString(Function.name(fn))
    case "sum" then (evalBinaryAdd, Expression.makeZero(ty));
    case "product" then (evalBinaryMul, Expression.makeOne(ty));
    case "min" then (evalBuiltinMin2, Expression.makeMaxValue(ty));
    case "max" then (evalBuiltinMax2, Expression.makeMinValue(ty));
    else
      algorithm
        Error.assertion(false, getInstanceName() + " got unknown reduction function " +
          AbsynUtil.pathString(Function.name(fn)), sourceInfo());
      then
        fail();
  end match;

  result := Expression.foldReduction(exp, iters, default_exp,
    function evalExp(target = noTarget), red_fn);
end evalReduction;

function evalSize
  input Expression exp;
  input Option<Expression> optIndex;
  input EvalTarget target;
  output Expression outExp;
protected
  Expression index_exp;
  Integer index;
  TypingError ty_err;
  Dimension dim;
  Type ty;
  SourceInfo info;
  array<Expression> arr;
algorithm
  info := EvalTarget.getInfo(target);

  if isSome(optIndex) then
    // Evaluate the index.
    index_exp := evalExp(Util.getOption(optIndex), target);
    index := Expression.toInteger(index_exp);

    // Get the index'd dimension of the expression.
    (dim, _, ty_err) := Typing.typeExpDim(exp, index, NFInstContext.CLASS, info);
    Typing.checkSizeTypingError(ty_err, exp, index, info);

    // Return the size expression for the found dimension.
    outExp := Dimension.sizeExp(dim);
    outExp := evalExp(outExp, target);
  else
    (outExp, ty) := Typing.typeExp(exp, NFInstContext.CLASS, info);
    arr := Array.mapList(Type.arrayDims(ty), Dimension.sizeExp);
    Array.mapNoCopy(arr, function evalExp(target = target));
    dim := Dimension.fromInteger(arrayLength(arr), Variability.PARAMETER);
    outExp := Expression.makeArray(Type.ARRAY(Type.INTEGER(), {dim}), arr);
  end if;
end evalSize;

function evalSubscriptedExp
  input Expression exp;
  input list<Subscript> subscripts;
  input EvalTarget target;
  output Expression result;
protected
  list<Subscript> subs;
algorithm
  result := match exp
    case Expression.RANGE()
      then Expression.RANGE(exp.ty,
                            evalExp(exp.start, target),
                            Util.applyOption(exp.step, function evalExp(target = target)),
                            evalExp(exp.stop, target));

    else evalExp(exp, target);
  end match;

  subs := list(Subscript.mapShallowExp(s, function evalExp(target = target)) for s in subscripts);
  result := Expression.applySubscripts(subs, result);
end evalSubscriptedExp;

function evalRecordElement
  input Expression exp;
  input EvalTarget target;
  output Expression result;
protected
  Expression e;
  Integer index;
algorithm
  Expression.RECORD_ELEMENT(recordExp = e, index = index) := exp;
  e := evalExp(e, target);

  try
    result := Expression.mapSplitExpressions(e,
      function Expression.nthRecordElement(index = index));
  else
    Error.assertion(false, getInstanceName() + " could not evaluate " +
      Expression.toString(exp), sourceInfo());
  end try;
end evalRecordElement;

function evalRecordElement2
  input Expression exp;
  input Integer index;
  output Expression result;
algorithm
  result := match exp
    case Expression.RECORD()
      then listGet(exp.elements, index);
  end match;
end evalRecordElement2;

protected

function printUnboundError
  input Component component;
  input EvalTarget target;
  input Expression exp;
protected
  EvalTargetData extra;
algorithm
  if not EvalTarget.hasInfo(target) then
    return;
  end if;

  () := match target.extra
    case SOME(extra as EvalTargetData.DIMENSION_DATA())
      algorithm
        Error.addSourceMessage(Error.STRUCTURAL_PARAMETER_OR_CONSTANT_WITH_NO_BINDING,
          {Expression.toString(extra.exp), InstNode.name(extra.component)}, target.info);
      then
        fail();

    case _
      guard InstContext.inCondition(target.context)
      algorithm
        Error.addSourceMessage(Error.CONDITIONAL_EXP_WITHOUT_VALUE,
          {Expression.toString(exp)}, target.info);
      then
        fail();

    else
      algorithm
        // check if we have a parameter with (fixed = true), annotation(Evaluate = true) and no binding
        if listMember(Component.variability(component), {Variability.STRUCTURAL_PARAMETER, Variability.PARAMETER}) and
           Util.getOptionOrDefault(Component.getEvaluateAnnotation(component), false)
        then
          // only add an error if fixed = true
          if Component.isFixed(component) then
            Error.addMultiSourceMessage(Error.UNBOUND_PARAMETER_EVALUATE_TRUE,
              {Expression.toString(exp) + "(fixed = true)"},
              {InstNode.info(ComponentRef.node(Expression.toCref(exp))), EvalTarget.getInfo(target)});
          end if;
        else // constant with no binding
          Error.addMultiSourceMessage(Error.UNBOUND_CONSTANT,
            {Expression.toString(exp)},
            {InstNode.info(ComponentRef.node(Expression.toCref(exp))), EvalTarget.getInfo(target)});
          fail();
        end if;
      then
        ();

  end match;
end printUnboundError;

function printWrongArgsError
  input String evalFunc;
  input list<Expression> args;
  input SourceInfo info;
algorithm
  Error.addInternalError(evalFunc + " got invalid arguments " +
    List.toString(args, Expression.toString, "", "(", ", ", ")", true), info);
end printWrongArgsError;

annotation(__OpenModelica_Interface="frontend");
end NFCeval;
