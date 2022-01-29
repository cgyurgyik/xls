// Copyright 2022 The XLS Authors
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

#include "xls/codegen/block_metrics_generator.h"

#include "gtest/gtest.h"
#include "xls/codegen/xls_metrics.pb.h"
#include "xls/common/status/matchers.h"
#include "xls/ir/block.h"
#include "xls/ir/function_builder.h"
#include "xls/ir/ir_parser.h"
#include "xls/ir/package.h"
#include "xls/ir/type.h"

namespace xls {
namespace verilog {
namespace {

TEST(BlockMetricsGeneratorTest, ZeroRegisters) {
  Package package("test");

  Type* u32 = package.GetBitsType(32);
  BlockBuilder bb("test_block", &package);
  BValue a = bb.InputPort("a", u32);
  BValue b = bb.InputPort("b", u32);
  bb.OutputPort("z", bb.Subtract(a, b));

  XLS_ASSERT_OK_AND_ASSIGN(Block * block, bb.Build());

  XLS_ASSERT_OK_AND_ASSIGN(BlockMetricsProto proto,
                           GenerateBlockMetrics(block));

  EXPECT_EQ(proto.flop_count(), 0);
}

TEST(BlockMetricsGeneratorTest, PipelineRegisters) {
  Package package("test");

  Type* u32 = package.GetBitsType(32);
  BlockBuilder bb("test_block", &package);

  XLS_ASSERT_OK(bb.block()->AddClockPort("clk"));
  BValue rst = bb.InputPort("rst", package.GetBitsType(1));

  BValue a = bb.InputPort("a", u32);
  BValue b = bb.InputPort("b", u32);
  BValue c = bb.Subtract(a, b);

  BValue p0_c = bb.InsertRegister("p0_c", c, rst,
                                  xls::Reset{.reset_value = Value(UBits(0, 32)),
                                             .asynchronous = false,
                                             .active_low = false});

  BValue p1_c = bb.InsertRegister("p1_c", p0_c, rst,
                                  xls::Reset{.reset_value = Value(UBits(0, 32)),
                                             .asynchronous = false,
                                             .active_low = false});

  bb.OutputPort("z", p1_c);

  XLS_ASSERT_OK_AND_ASSIGN(Block * block, bb.Build());

  XLS_ASSERT_OK_AND_ASSIGN(BlockMetricsProto proto,
                           GenerateBlockMetrics(block));

  EXPECT_EQ(proto.flop_count(), 64);
}

}  // namespace
}  // namespace verilog
}  // namespace xls