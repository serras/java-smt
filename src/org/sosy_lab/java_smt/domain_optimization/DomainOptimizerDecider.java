/*
 *  JavaSMT is an API wrapper for a collection of SMT solvers.
 *  This file is part of JavaSMT.
 *
 *  Copyright (C) 2007-2016  Dirk Beyer
 *  All rights reserved.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

package org.sosy_lab.java_smt.domain_optimization;


import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.sosy_lab.java_smt.api.BooleanFormula;
import org.sosy_lab.java_smt.api.Formula;
import org.sosy_lab.java_smt.api.FormulaManager;
import org.sosy_lab.java_smt.api.IntegerFormulaManager;
import org.sosy_lab.java_smt.api.SolverException;
import org.sosy_lab.java_smt.api.visitors.DefaultFormulaVisitor;
import org.sosy_lab.java_smt.api.visitors.FormulaVisitor;
import org.sosy_lab.java_smt.api.visitors.TraversalProcess;

public class DomainOptimizerDecider {

  private final DomainOptimizer opt;
  private final DomainOptimizerSolverContext delegate;

  private List<Formula> variables = new ArrayList<>();

  public DomainOptimizerDecider(
      DomainOptimizer pOpt,
      DomainOptimizerSolverContext pDelegate) {
    opt = pOpt;
    delegate = pDelegate;
  }

  enum degreesOfSatisfiability {
    unsat,
    sat,
    tautology
  }


    public List<Formula> performSubstitutions(Formula f) {
      FormulaManager fmgr = delegate.getFormulaManager();
      IntegerFormulaManager imgr = fmgr.getIntegerFormulaManager();
      List<Formula> variables = new ArrayList<>();
      List<Formula> substitutedFormulas = new ArrayList<>();

      FormulaVisitor<TraversalProcess> varExtractor =
          new DefaultFormulaVisitor<>() {

            @Override
            protected TraversalProcess visitDefault(Formula f) {
              return TraversalProcess.CONTINUE;
            }

            @Override
            public TraversalProcess visitFreeVariable(Formula formula, String name) {
              variables.add(formula);
              return TraversalProcess.CONTINUE;
            }
          };

      fmgr.visitRecursively(f, varExtractor);
      
      this.variables = variables;
      int[][] decisionMatrix = constructDecisionMatrix();

      for (int i = 0; i < Math.pow(2,variables.size()); i++) {
        List<Map<Formula,Formula>> substitutions = new ArrayList<>();
        for (int j = 0; j < variables.size(); j++) {
          Formula var = variables.get(j);
          SolutionSet domain = opt.getSolutionSet(var);
          Map<Formula,Formula> substitution = new HashMap<>();
          if (decisionMatrix[j][i] == 1) {
            substitution.put(var,imgr.makeNumber(domain.getUpperBound()));
          }
          else if (decisionMatrix[j][i] == 0) {
            substitution.put(var,imgr.makeNumber(domain.getLowerBound()));
          }
          substitutions.add(substitution);
        }
        Formula buffer = f;
        for (Map<Formula,Formula> substitution : substitutions) {
          f = fmgr.substitute(f,substitution);
        }
        substitutedFormulas.add(f);
        f = buffer;
      }
      return substitutedFormulas;
    }


    public degreesOfSatisfiability decide(BooleanFormula query) throws InterruptedException, SolverException {
      List<Formula> satisfiableQueries = new ArrayList<>();
      DomainOptimizerProverEnvironment wrapped = opt.getWrapped();
      List<Formula> readyForDecisisionPhase = performSubstitutions(query);
      for (Formula f : readyForDecisisionPhase) {
        wrapped.addConstraint((BooleanFormula) f);
        System.out.println(f.toString());
        if (!wrapped.isUnsat()) {
          System.out.println(f.toString());
          satisfiableQueries.add(f);
        }
        wrapped.close();
      }
      if (satisfiableQueries.size() == readyForDecisisionPhase.size()) {
        return degreesOfSatisfiability.tautology;
      }
      if (satisfiableQueries.size() > 0) {
        return degreesOfSatisfiability.sat;
      }
      return degreesOfSatisfiability.unsat;
    }


    public int[][] constructDecisionMatrix() {
    int[][] decisionMatrix = new int[variables.size()][(int) Math.pow(2,variables.size())];
        int rows = (int) Math.pow(2,variables.size());
        for (int i=0; i<rows; i++) {
          for (int j=variables.size() - 1; j>=0; j--) {
            decisionMatrix[j][i] = (i/(int) Math.pow(2, j))%2;
          }
        }
      return decisionMatrix;
    }



}