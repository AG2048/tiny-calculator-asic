# Tiny Calculator cocotb testbench

The testbench uses [cocotb](https://docs.cocotb.org/en/stable/) to verify the individual RTL modules and the complete Tiny Tapeout pin interface. It generates physical keypad and control-button activity, applies randomized valid/ready backpressure, predicts calculator behavior with a Python reference model, decodes the serialized seven-segment stream, and checks the selected-operation outputs.

For hardware setup and the physical falling-edge `SRCLK` requirement, see the [ASIC bring-up guide](../docs/info.md). The testbench is a functional digital model; it is not an electrical timing model.

## Files and structure

| File | Purpose |
| --- | --- |
| `tb.v` | Instantiates either the RTL top level or gate-level netlist and exposes convenient named wires to cocotb |
| `test.py` | Drivers, monitors, random sequence/reference model, and all cocotb tests |
| `Makefile` | Selects RTL or gate-level sources, simulator, sample count, timeout, and waveform generation |
| `requirements.txt` | Python packages required by the tests |
| `tb.gtkw` | Unused default/template GTKWave layout; its hierarchy paths may be stale |

### Python drivers and monitors

`test.py` is organized around reusable writers, readers, and reference helpers:

- `ButtonPressGenerator` drives the real top-level keypad and control interfaces. It waits for the matching one-hot WL before asserting a matrix BL, can assert multiple keys, varies hold/release timing, and can wait for the reader's `o_valid` to clear before beginning another event.
- `ButtonValueReader` consumes the button reader's five-bit valid/ready interface, decodes the event code back into `0`–`F`, an operator, `EQ`, `AC`, or `NEG`, and compares the received queue against generated presses.
- `OutputDisplay` models a SIPO's hidden shift register, storage latch, and active-low output enable. It decodes five groups of active-high `abcdefg` bits into hexadecimal text, minus, blank, or `Err` and compares visible values with the expected display sequence.
- `test_sequence_generator` creates normal, chained, after-equals, or unconstrained random key sequences, with optional `NEG`, overflow-oriented input, and random `AC` events.
- `test_sequence_expected_display_and_op_status` is the calculator reference model. It predicts every displayed value and the four operation-status outputs for the generated key sequence.
- `print_generated_test_sequence_and_expected_results` is a standalone debug helper for inspecting generated sequences and expectations; it is not a cocotb test.

## Cocotb tests

An ordinary RTL run executes five parameterized test functions.

All cocotb tests use a 10 µs clock period (100 kHz) as a convenient functional-simulation rate. That test frequency is not a measured silicon operating limit and is separate from the tentative 5 kHz first-bring-up suggestion.

### `test_button_reader`

Tests `button_reader` directly through its internal module hierarchy. It checks matrix/control decoding, priority cases, release-latched event generation, held buttons, and valid/ready behavior.

Variants:

- `ready_timing`
  - `ALWAYS_ON`: consumer always accepts events.
  - `RANDOM_READY`: consumer inserts random 1–10-cycle delays/backpressure.
- `button_press_mode`
  - `SINGLE_PRESS`: one key is held and released with randomized duration and gap.
  - `MULTI_PRESS`: the expected key is pressed with lower-priority keys. For a digit, the additional keys are from the same row; for a control input, lower-priority controls and matrix keys may also be present.
  - `MULTI_HOLD_LATE_RELEASE`: many randomly selected keys may overlap, but the expected key is deliberately released last. This exercises the reader's last-observed/release behavior across rows and control inputs.
  - `SHORTEST_SINGLE_PRESS`: a control is high for one cycle, or a matrix BL is asserted for exactly one matching WL slot.
- `input_order`
  - `IN_ORDER`: traverses the priority-ordered list of controls and digits.
  - `RANDOM_ORDER`: chooses each expected event randomly.

The default parameterization holds buttons and inserts inter-press gaps for randomized 5–50-cycle intervals; randomized ready delay is 1–10 cycles.

This test verifies implemented resolution behavior, not mechanical debounce. It does not model switch contact bounce.

### `test_output_driver`

Tests `output_driver` directly. It supplies 16-bit values and checks the 35 shifted `abcdefg` bits, leading-zero suppression, minus placement, storage latch, `OE_n`, and `Err` encoding.

Variants:

- `valid_timing`: input valid is always asserted or randomized.
- `test_neg_displays`: generate unsigned-only values or include negative signed display values.
- `input_order`: sequential/wrapping values or random values.
- `allow_error`: optionally replace about 10% of samples with an error display request.

### `test_alu`

Tests `alu` directly through both valid/ready interfaces. It predicts 16-bit add, subtract, multiply, divide, division-by-zero, signed quotient behavior, and wraparound.

Variants:

- `test_only_certain_ops`: `+`, `-`, `*`, `/`, or `ALL`.
- `test_2s_complement`: unsigned or signed inputs/results.
- `input_value_range_width`: generate values from a 4-bit or full 16-bit range.
- `operation_sequence`: cycle sequentially through enabled operations or select them randomly.
- `input_valid_timing`: always-valid or randomized producer backpressure.
- `output_ready_timing`: always-ready or randomized consumer backpressure.

Division vectors have an intentional chance of B being zero. Successful signed division is expected to truncate toward zero. Results outside the representable range are reduced to their low 16 bits.

### `test_core`

Tests `calculator_core` directly without physical keypad scanning or serial shifting. It drives encoded button events, models ALU and display ready/valid timing, and checks display transactions plus operation-status outputs against the Python calculator model.

Variants:

- `test_2s_complement`: unsigned or signed calculator mode.
- `test_input_with_overflow`: keep generated number input within range or deliberately allow sequences that attempt to exceed it.
- `include_neg_button`
  - `NO_NEGATIVE_INPUT`: never press `NEG`.
  - `NEGATIVE_INPUT_AFTER_VAL_INPUT`: press `NEG` only after a number/result.
  - `NEGATIVE_INPUT_IN_BETWEEN_VAL_INPUT`: allow `NEG` throughout operand entry.
- `test_sequence_type`
  - `ONE`: `AC`, A, operator, B, `EQ`, `AC`.
  - `SEQUENCE_BY_OP`: continue `number, operator, number, operator...` to exercise left-to-right chaining.
  - `SEQUENCE_AFTER_EQ`: continue from results with `operator, number, EQ...`.
  - `RANDOM_BUTTON_PRESS`: choose any calculator button, including unusual but legal sequences.
- `allow_random_ac_presses`: clear only at planned sequence boundaries or inject `AC` during generated sequences.
- `input_valid_timing` and `output_ready_timing`: always asserted or randomized handshake timing.
- `sequence_length`: number of number/operator/equals actions in each generated sample before its final clear.

Because these parameter combinations and sequences are comparatively slow, the test uses `max(NUM_SAMPLES / 200, 1)` generated samples per parameter combination.

### `test_top`

This is the complete system test and the **only test enabled for gate-level simulation**. It drives `ui_in` and `uio_in` through the physical keypad/control mapping, watches `uo_out` and `uio_out`, decodes the serialized display, and compares both display values and operation-status LEDs with the reference model.

It combines the core variants with all four `ButtonPressGenerator` modes, including same-row priority, overlapping presses, late release, and a one-WL-slot minimum matrix press. In this test the generator cannot use the internal button-reader `o_valid`, so it waits `NUM_DISPLAYS × 7 + 2 × DATA_WIDTH + 10` cycles (77 cycles for this design) before another generated press. Like the core test, it uses `max(NUM_SAMPLES / 200, 1)` generated samples per parameter combination.

## RTL setup

Install:

- Python 3.11 or another version supported by the pinned cocotb dependencies.
- Icarus Verilog (`iverilog`) for the default simulator.
- The packages from `requirements.txt`.
- GTKWave or Surfer only if waveform viewing is desired.

From the `test` directory:

```sh
python -m pip install -r requirements.txt
make -B
```

`make -B` recompiles and executes every RTL test/parameter combination. `make clean` removes cocotb simulator output before a new run.

## Runtime controls

The Makefile exports these primary controls:

| Variable | Default | Meaning |
| --- | --- | --- |
| `SIM` | `icarus` | cocotb simulator backend |
| `WAVES` | `1` | enable waveform dumping where supported |
| `NUM_SAMPLES` | `400` | sample count used directly by button, output-driver, and ALU tests; core/top scale it down |
| `TIMEOUT_MS` | `10000` | per-test timeout in simulated/testbench milliseconds |

Examples:

```sh
make -B NUM_SAMPLES=100 TIMEOUT_MS=10000
make -B SIM=icarus WAVES=0
```

The randomized tests do not currently expose a fixed random seed through the Makefile. Preserve cocotb's reported seed when reproducing a failure.

Outputs normally include:

- `results.xml`: cocotb test results consumed by CI.
- `tb.vcd`: waveform dump.
- `sim_build/rtl`: compiled RTL simulation artifacts.

## Viewing waveforms

Using GTKWave:

```sh
gtkwave tb.vcd
```

`tb.gtkw` is not used by the Makefile or CI and is only a default/template layout. It may be loaded manually if useful, but its saved hierarchy paths are not maintained as part of the testbench.

Using Surfer:

```sh
surfer tb.vcd
```

## Gate-level simulation

When `GATES=yes`:

- `test_button_reader`, `test_output_driver`, `test_alu`, and `test_core` are skipped because they reach into named RTL submodule hierarchy that is not preserved in the synthesized netlist.
- `test_top` remains enabled and is the one and only gate-level test.
- The Makefile defines `GL_TEST`, `FUNCTIONAL`, `USE_POWER_PINS`, `SIM_BUILD`, and unit-delay settings.
- `tb.v` supplies `VPWR` and `VGND` to the synthesized design.

A local gate-level run requires:

1. A SKY130 PDK installation with `PDK_ROOT` pointing to the directory containing `sky130A/libs.ref/sky130_fd_sc_hd/verilog`.
2. A hardened functional netlist copied to `test/gate_level_netlist.v`.
3. The same Python/cocotb and simulator dependencies used for RTL.

Then run from `test`:

```sh
make clean
make -B GATES=yes
```

Gate-level testing is normally performed by `.github/workflows/gds.yaml`. The Tiny Tapeout GDS action hardens the design, and its `gl_test` action supplies the generated netlist expected by the Makefile before running the top-level test. Local hardening through the Tiny Tapeout support tools is also possible; follow the current [Tiny Tapeout local-hardening guide](https://www.tinytapeout.com/guides/local-hardening/) rather than assuming an old `runs/` directory layout.

The separate `.github/workflows/test.yaml` workflow installs Icarus and the Python requirements, runs the RTL Makefile, checks `results.xml` for failures, and uploads the available VCD and XML artifacts. Its results can be viewed and downloaded for local gate-level testing.

## Why the model samples rising `SRCLK`

`OutputDisplay.hidden_registers_watcher` waits for `RisingEdge(srclk)`. This is an intentional idealized functional model of the RTL: in zero-delay simulation, the monitor treats `SER` as the intended previous-cycle value immediately before that edge, then shifts it into its hidden register.

This monitor does **not** prove physical setup time. In silicon, the `SER` and `SRCLK` pads are reached through different logic and routing from the same clock event, so their relative skew is not guaranteed. The external hardware must therefore capture `SER` on the falling edge of `SRCLK`, as required by the [bring-up-guide erratum](../docs/info.md#required-srclk-falling-edge-capture). Falling-edge sampling gives the data roughly half a clock period to settle while preserving the same 35-bit functional order.

## Interpreting failures

- A button-reader mismatch usually indicates priority, scan alignment, release timing, or ready/valid behavior.
- An output-driver mismatch identifies a seven-segment order, sign position, latch, blanking, or error-pattern problem.
- An ALU mismatch isolates arithmetic, sign conversion, wraparound, or handshake behavior.
- A core mismatch points to the calculator state/reference model without matrix or serial timing.
- A top-level-only mismatch points to physical pin mapping, integration, button generation, serialization, or synthesized behavior.
