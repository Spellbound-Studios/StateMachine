// Copyright (c) Spellbound Studios. All rights reserved.

using System.Globalization;
using System.Text;
using Spellbound.Core.Operations;

namespace Spellbound.StateMachine {
    public static class StateMachineOperations {
        [Operation("states", "Lists the states of the shared registry by name and hash, in registry order.",
            OperationEffect.Reads, Audience = OperationAudiences.Anyone)]
        public static OperationResult States(OperationContext context,
            [Argument("How many states to skip from the start.")] int offset = 0,
            [Argument("How many states to list.")] int limit = 50) {
            if (offset < 0 || limit < 1) {
                return OperationResult.Invalid("--offset is 0 or more and --limit is 1 or more, not --offset "
                                               + Number(offset) + " --limit " + Number(limit)
                                               + "\nRun: statemachine states");
            }

            var states = StateMachineKit.Registry.All;
            var table = new OperationTable("hash", "name");
            var listed = 0;

            for (var index = offset; index < states.Count && listed < limit; index++) {
                var state = states[index];

                if (state == null)
                    continue;

                table.AddRow(state.Hash, state.name);
                listed++;
            }

            var text = new StringBuilder();
            text.Append(Number(states.Count)).Append(states.Count == 1 ? " state" : " states")
                .Append(" in the registry");

            if (listed < states.Count) {
                text.Append(", ").Append(Number(listed)).Append(" listed from ").Append(Number(offset));
            }

            if (listed > 0) {
                text.Append('\n').Append(table.ToText());
            }

            return OperationResult.Success(text.ToString());
        }

        private static string Number(int value) => value.ToString(CultureInfo.InvariantCulture);
    }
}
