// Copyright 2021 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef XLS_DSLX_Z3_DSLX_TRANSLATOR_H_
#define XLS_DSLX_Z3_DSLX_TRANSLATOR_H_

#include "xls/dslx/symbolic_type.h"
#include "../z3/src/api/z3.h"
#include "../z3/src/api/z3_api.h"

namespace xls::solvers::z3 {

using dslx::SymbolicType;

class DslxTranslator {
 public:
  // Creates a translator and uses it to translate the given expression tree
  // into a Z3 AST.
  static absl::StatusOr<std::unique_ptr<DslxTranslator>> CreateAndTranslate(
      SymbolicType* predicate);

  ~DslxTranslator();

  // Returns the Z3 value (or set of values) corresponding to the given Node.
  Z3_ast GetTranslation(const SymbolicType* source);

  // Sets the amount of time to allow Z3 to execute before aborting.
  void SetTimeout(absl::Duration timeout);

  Z3_context ctx() { return ctx_; }

  // Helper functions for translating DSLX operators to their Z3
  // representations.
  absl::Status HandleAdd(SymbolicType* sym);
  absl::Status HandleConcat(SymbolicType* sym);
  absl::Status HandleEq(SymbolicType* sym);
  absl::Status HandleLiteral(SymbolicType* sym);
  absl::Status HandleAnd(SymbolicType* sym);
  absl::Status HandleOr(SymbolicType* sym);
  absl::Status HandleXor(SymbolicType* sym);
  absl::Status HandleNe(SymbolicType* sym);
  absl::Status HandleParam(SymbolicType* sym);
  absl::Status HandleGe(SymbolicType* sym);
  absl::Status HandleShll(SymbolicType* sym);
  absl::Status HandleShra(SymbolicType* sym);
  absl::Status HandleShrl(SymbolicType* sym);
  absl::Status HandleGt(SymbolicType* sym);
  absl::Status HandleLe(SymbolicType* sym);
  absl::Status HandleLt(SymbolicType* sym);
  absl::Status HandleMul(SymbolicType* sym);
  absl::Status HandleDiv(SymbolicType* sym);
  absl::Status HandleSub(SymbolicType* sym);

 private:
  DslxTranslator(Z3_config config);

  // Records the mapping of the specified DXLS node to Z3 value.
  absl::Status NoteTranslation(SymbolicType* node, Z3_ast translated);

  // Converts a DXLS function parameter into a Z3 param type.
  absl::StatusOr<Z3_ast> CreateZ3Param(SymbolicType* sym);

  // Recursive call to translate XLS literals into Z3 form.
  absl::StatusOr<Z3_ast> TranslateLiteralValue(SymbolicType* sym);

  // Common multiply handling.
  absl::Status HandleMulHelper(SymbolicType* sym, bool is_signed);

  // Gets the translation of the given node. Crashes if "node" has not already
  // been translated. The following functions are short-cuts that assume the
  // node is of the indicated type.
  Z3_ast GetValue(SymbolicType* sym);
  Z3_ast GetBitVec(SymbolicType* sym);
  int64_t GetBitVecCount(SymbolicType* sym);

  // Does the _actual_ work of processing binary and shift operations.
  template <typename FnT>
  absl::Status HandleBinary(SymbolicType* sym, FnT f);
  template <typename FnT>
  absl::Status HandleShift(SymbolicType* sym, FnT f);

  absl::flat_hash_map<const SymbolicType*, Z3_ast> translations_;

  Z3_config config_;
  Z3_context ctx_;
};

// Visitor methods for traversing the expression tree nodes and invoking the
// corresponding Handlers for Z3 translation.
absl::Status VisitSymbolicTree(DslxTranslator* translator, SymbolicType* sym);
absl::Status ProcessSymbolicLeaf(DslxTranslator* translator, SymbolicType* sym);
absl::Status ProcessSymbolicNode(DslxTranslator* translator, SymbolicType* sym);

// Attempts to prove the logic formula in "predicate" within the duration
// "timeout" and prints the (if existing) set of inputs that satisfy the
// formula.
absl::Status TryProve(SymbolicType* predicate, bool negate_predicate,
                      absl::Duration timeout);


}  // namespace xls::solvers::z3

#endif  // XLS_DSLX_Z3_DSLX_TRANSLATOR_H_