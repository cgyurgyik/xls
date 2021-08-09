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

#ifndef XLS_IR_FORMAT_STRINGS_H_
#define XLS_IR_FORMAT_STRINGS_H_

#include "absl/types/variant.h"
#include "xls/ir/format_preference.h"

namespace xls {

// When building output based on a format string, there are two kinds of
// steps involved: printing string fragments and printing arguments according
// to their requested format.
using FormatStep = absl::variant<std::string, FormatPreference>;

// Parse a format string into the steps required to build output using it.
// Example: "x is {} in the default format." would parse into the steps
// {"x is ", FormatPreference::kDefault, " in the default format."}
absl::StatusOr<std::vector<FormatStep>> ParseFormatString(
    absl::string_view format_string);

}  // namespace xls

#endif  // XLS_IR_FORMAT_STRINGS_H_