# SPDX-FileCopyrightText: © 2025 Andy Gong
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.handle import Force, Release, Freeze
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, ValueChange, Edge, Timer, Combine, First, with_timeout
import os
import random

DATA_WIDTH = 16

class ButtonValueReader:
    def __init__(self, signal_data, signal_ready, signal_valid, clk, ready_mode="ALWAYS_ON", num_reads=100, random_delay_min_cyc=1, random_delay_max_cyc=10, expected_values_list=None):
        self._signal_data = signal_data
        self._signal_ready = signal_ready
        self._signal_valid = signal_valid
        self._clk = clk
        self._ready_mode = ready_mode
        self._random_delay_min_cyc = random_delay_min_cyc
        self._random_delay_max_cyc = random_delay_max_cyc
        self.data_queue = []
        self.expected_values_list = expected_values_list
        self.value_decoded = {
            0x0: '0',
            0x1: '1',
            0x2: '2',
            0x3: '3',
            0x4: '4',
            0x5: '5',
            0x6: '6',
            0x7: '7',
            0x8: '8',
            0x9: '9',
            0xA: 'A',
            0xB: 'B',
            0xC: 'C',
            0xD: 'D',
            0xE: 'E',
            0xF: 'F',
            0b10000: '+',
            0b10001: '-',
            0b10010: '*',
            0b10011: '/',
            0b10100: '=',
            0b10101: 'AC',
            0b10110: '(-)'
        }
        self._num_reads = num_reads

    async def _read_values(self):
        cocotb.log.info(f"ButtonValueReader: Starting to read {self._num_reads} values with ready_mode={self._ready_mode}")
        while True:
            await RisingEdge(self._clk)
            if self._signal_valid.value == 1 and self._signal_ready.value == 1:
                data = self._signal_data.value
                decoded_data = self.value_decoded.get(int(data), f"UNKNOWN({int(data)})")
                self.data_queue.append(decoded_data)
                if self.expected_values_list is not None:
                    expected_data = self.expected_values_list[len(self.data_queue) - 1]
                    if decoded_data != expected_data:
                        cocotb.log.info(f"ButtonValueReader: Mismatch at read {len(self.data_queue)}: expected {expected_data}, got {decoded_data}")
                cocotb.log.info(f"ButtonValueReader: Read data {decoded_data} ({len(self.data_queue)}/{self._num_reads})")
                if len(self.data_queue) >= self._num_reads:
                    break

    async def _set_ready(self, ready_mode):
        await FallingEdge(self._clk)
        if ready_mode == "ALWAYS_ON":
            while True:
                self._signal_ready.value = Force(1)
                await FallingEdge(self._clk)
                if len(self.data_queue) >= self._num_reads:
                    break
        elif ready_mode == "RANDOM_READY":
            while True:
                self._signal_ready.value = Force(random.choice([0, 1]))
                await ClockCycles(self._clk, random.randint(self._random_delay_min_cyc, self._random_delay_max_cyc))
                await FallingEdge(self._clk)
                if len(self.data_queue) >= self._num_reads:
                    break
        else:
            raise ValueError(f"Unknown ready_mode: {ready_mode}")


class ButtonPressGenerator:
    def __init__(self, clk, o_word_lines, i_bit_lines, i_ac_pin, i_add_pin, i_sub_pin, i_mul_pin, i_div_pin, i_eq_pin, i_neg_pin, o_valid=None, button_press_mode="SINGLE_PRESS", input_order="IN_ORDER", num_samples=100, button_hold_random_min_cyc=5, button_hold_random_max_cyc=200, inter_press_gap_random_min_cyc=5, inter_press_gap_random_max_cyc=200, no_valid_delay_cyc=100):
        self.clk = clk
        self.o_word_lines = o_word_lines
        self.i_bit_lines = i_bit_lines
        self.i_ac_pin = i_ac_pin
        self.i_add_pin = i_add_pin
        self.i_sub_pin = i_sub_pin
        self.i_mul_pin = i_mul_pin
        self.i_div_pin = i_div_pin
        self.i_eq_pin = i_eq_pin
        self.i_neg_pin = i_neg_pin
        self.o_valid = o_valid  # Used to make sure press only happen when not valid
        self.button_press_mode = button_press_mode
        self.input_order = input_order
        self.num_samples = num_samples
        self.button_hold_random_min_cyc = button_hold_random_min_cyc
        self.button_hold_random_max_cyc = button_hold_random_max_cyc
        self.inter_press_gap_random_min_cyc = inter_press_gap_random_min_cyc
        self.inter_press_gap_random_max_cyc = inter_press_gap_random_max_cyc
        self.no_valid_delay_cyc = no_valid_delay_cyc
        self.bit_line_value = 0b0000  # this value is OR'd by all drivers after rising edge, and centrally written to after falling edge and cleared to 0
        self.numbers_pressed_cycles_left = {} # {"digit": [total_cycles, cycles_done]}
        # Order in possible_signals is also the hierachy of priority.
        self.possible_signals = [
            "+",
            "-", "*",
            "/", "=",
            "AC", "(-)",
            "3",
            "2",
            "1",
            "0",
            "7",
            "6",
            "5",
            "4",
            "B",
            "A",
            "9",
            "8",
            "F",
            "E",
            "D",
            "C"
        ]
        self.button_bit_line_mapping = { # value: (word_line_value, bit_line_value)
            "0": (0b0001, 0b0001),
            "1": (0b0001, 0b0010),
            "2": (0b0001, 0b0100),
            "3": (0b0001, 0b1000),
            "4": (0b0010, 0b0001),
            "5": (0b0010, 0b0010),
            "6": (0b0010, 0b0100),
            "7": (0b0010, 0b1000),
            "8": (0b0100, 0b0001),
            "9": (0b0100, 0b0010),
            "A": (0b0100, 0b0100),
            "B": (0b0100, 0b1000),
            "C": (0b1000, 0b0001),
            "D": (0b1000, 0b0010),
            "E": (0b1000, 0b0100),
            "F": (0b1000, 0b1000)
        }
        self.button_presses_generated = []
        self._generate_presses()

    async def _force_bit_lines(self):
        # cocotb.log.info("Starting Button Press Generator _force_bit_lines coroutine")
        cocotb.log.info(f"Pressing following digits: {self.numbers_pressed_cycles_left.keys()}")
        # Wait until o_valid is low for 5 cycles
        if self.o_valid is not None:
            valid_low_cycles = 0
            while valid_low_cycles < 5:
                await RisingEdge(self.clk)
                if self.o_valid.value == 0:
                    valid_low_cycles += 1
                else:
                    valid_low_cycles = 0
        else:
            await ClockCycles(self.clk, self.no_valid_delay_cyc)  # Wait 100 cycles if no o_valid provided
        # Write to i_bit_lines based on numbers_pressed_cycles_left
        while True:
            await FallingEdge(self.clk)
            word_lines_val = self.o_word_lines.value
            # Check mapping 
            self.bit_line_value = 0b0000  # reset
            digits_done = []
            for digit, (total_cycles, cycles_done) in self.numbers_pressed_cycles_left.items():
                if cycles_done < total_cycles:
                    wl_val, bl_val = self.button_bit_line_mapping[digit]
                    if word_lines_val == wl_val:
                        self.bit_line_value |= bl_val
            # Write the bit line value to the output
            self.i_bit_lines.value = Force(self.bit_line_value)
            # cocotb.log.info(f"Set i_bit_lines to {self.bit_line_value} for word_lines {word_lines_val}")
            # Update cycles done
            for digit in self.numbers_pressed_cycles_left.keys():
                self.numbers_pressed_cycles_left[digit][1] += 1
                if self.numbers_pressed_cycles_left[digit][1] > self.numbers_pressed_cycles_left[digit][0]:
                    digits_done.append(digit)
            # Remove done digits
            for digit in digits_done:
                del self.numbers_pressed_cycles_left[digit]
            # If all digits are done, exit
            if len(self.numbers_pressed_cycles_left) == 0:
                # Force i_bit_lines to 0 before exiting
                self.i_bit_lines.value = Force(0b0000)
                break
    
    async def _force_op_pins(self, signal_name, hold_cycles):
        pin_map = {
            "AC": self.i_ac_pin,
            "+": self.i_add_pin,
            "-": self.i_sub_pin,
            "*": self.i_mul_pin,
            "/": self.i_div_pin,
            "=": self.i_eq_pin,
            "(-)": self.i_neg_pin
        }
        if signal_name not in pin_map:
            raise ValueError(f"Signal {signal_name} is not an operator pin.")
        pin = pin_map[signal_name]
        cocotb.log.info(f"Forcing operator pin {signal_name}")
        # Wait until o_valid is low for 5 cycles
        if self.o_valid is not None:
            valid_low_cycles = 0
            while valid_low_cycles < 5:
                await RisingEdge(self.clk)
                if self.o_valid.value == 0:
                    valid_low_cycles += 1
                else:
                    valid_low_cycles = 0
        else:
            await ClockCycles(self.clk, self.no_valid_delay_cyc)  # Wait 100 cycles if no o_valid provided
        # Force the pin high for a random hold time
        await FallingEdge(self.clk)
        pin.value = Force(1)
        for _ in range(hold_cycles):
            await FallingEdge(self.clk)
        pin.value = Force(0)
        # cocotb.log.info(f"Released operator pin {signal_name}")

    def _generate_presses(self):
        self.button_presses_generated = []
        for i in range(self.num_samples):
            if self.input_order == "IN_ORDER":
                signal_name = self.possible_signals[i % len(self.possible_signals)]
            elif self.input_order == "RANDOM_ORDER":
                signal_name = random.choice(self.possible_signals)
            else:
                raise ValueError(f"Unknown input_order: {self.input_order}")

            self.button_presses_generated.append(signal_name)

    async def _press_buttons(self):
        """Make signal corresponding to the button presses in button_presses_generated."""
        # Wait for a few cycles before starting
        for _ in range(10):
            await RisingEdge(self.clk)
        for i, signal_name in enumerate(self.button_presses_generated):
            # SINGLE PRESS: only 1 button is pressed.
            #    Hold for random time, release for random time.
            # MULTI PRESS: choose a few signals that have "lower priority" than the signal
            #    This includes any number for non-digit buttons, and digits with same upper-2-bits that are "lower" on the list (higher index).
            #    Press them all together for random time, release for random time. 
            # MULTI HOLD LATE RELEASE: Choose a random number of buttons, each hold for a random time, but make sure only release main button 4+ cycles later. 
            #TODO: need to make a coroutine / task that actually does the pressing and releasing (so that we can write multiple presses at once)
            
            # First delay by gap:
            gap_cycles = random.randint(self.inter_press_gap_random_min_cyc, self.inter_press_gap_random_max_cyc)
            for _ in range(gap_cycles):
                await RisingEdge(self.clk)

            cocotb.log.info(f"Pressing button {i+1}/{self.num_samples}: {signal_name} with mode {self.button_press_mode}")

            if self.button_press_mode == "SINGLE_PRESS":
                if signal_name in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]:
                    #TODO: add values to list and cycle count
                    self.numbers_pressed_cycles_left = {} # reset
                    self.numbers_pressed_cycles_left[signal_name] = [
                        random.randint(self.button_hold_random_min_cyc, self.button_hold_random_max_cyc),
                        0
                    ]
                    single_press_coro = cocotb.start_soon(self._force_bit_lines())
                    await single_press_coro
                else:
                    hold_cycles = random.randint(self.button_hold_random_min_cyc, self.button_hold_random_max_cyc)
                    op_press_coro = cocotb.start_soon(self._force_op_pins(signal_name, hold_cycles))
                    await op_press_coro
            elif self.button_press_mode == "MULTI_PRESS":
                self.numbers_pressed_cycles_left = {} # reset
                if signal_name in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]:
                    # expected signal is number, add it and lower priority numbers
                    main_index = self.possible_signals.index(signal_name)
                    cycles_to_hold = random.randint(self.button_hold_random_min_cyc, self.button_hold_random_max_cyc)
                    self.numbers_pressed_cycles_left[signal_name] = [
                        cycles_to_hold,
                        0
                    ]
                    # Add lower priority digits
                    for other_signal in self.possible_signals[main_index+1:((main_index-7)//4)*4 + 7 + 4]: # up to next value on same word line
                        if other_signal in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]:
                            if random.choice([True, False]):
                                self.numbers_pressed_cycles_left[other_signal] = [
                                    cycles_to_hold,
                                    0
                                ]
                    multi_press_coro = cocotb.start_soon(self._force_bit_lines())
                    await multi_press_coro
                else:
                    # Expected signal is operator. Randomly add any other operators with lower priority.
                    hold_cycles = random.randint(self.button_hold_random_min_cyc, self.button_hold_random_max_cyc)
                    main_index = self.possible_signals.index(signal_name)
                    op_pins = [signal_name]
                    for other_signal in self.possible_signals[main_index+1:]: # All lower priority
                        if other_signal in ["AC", "+", "-", "*", "/", "=", "(-)"]:
                            if random.choice([True, False]):
                                op_pins.append(other_signal)
                        else:
                            self.numbers_pressed_cycles_left[other_signal] = [
                                hold_cycles,
                                0
                            ]
                    op_press_coros = []
                    for op in op_pins:
                        op_press_coros.append(cocotb.start_soon(self._force_op_pins(op, hold_cycles)))
                    numbers_press_coro = cocotb.start_soon(self._force_bit_lines())
                    await Combine(*op_press_coros, numbers_press_coro)
            elif self.button_press_mode == "MULTI_HOLD_LATE_RELEASE":
                # The main button hs hold for a duration of random_time + max of other buttons' duration
                self.numbers_pressed_cycles_left = {} # reset
                op_pins = []
                max_hold_cycles = 0
                for signal in self.possible_signals:
                    if signal == signal_name:
                        continue
                    hold_cycles = random.randint(self.button_hold_random_min_cyc, self.button_hold_random_max_cyc)
                    if hold_cycles > max_hold_cycles:
                        max_hold_cycles = hold_cycles
                    if signal in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]:
                        if random.choice([True, False]):
                            self.numbers_pressed_cycles_left[signal] = [
                                hold_cycles,
                                0
                            ]
                    else:
                        if random.choice([True, False]):
                            op_pins.append((signal, hold_cycles))
                # Add main signal
                if signal_name in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]:
                    self.numbers_pressed_cycles_left[signal_name] = [
                        max_hold_cycles + random.randint(self.button_hold_random_min_cyc, self.button_hold_random_max_cyc),
                        0
                    ]
                else:
                    op_pins.append((signal_name, max_hold_cycles + random.randint(self.button_hold_random_min_cyc, self.button_hold_random_max_cyc)))
                    
                op_press_coros = []
                for op, hold_cycles in op_pins:
                    op_press_coros.append(cocotb.start_soon(self._force_op_pins(op, hold_cycles)))
                numbers_press_coro = cocotb.start_soon(self._force_bit_lines())
                await Combine(*op_press_coros, numbers_press_coro)
            elif self.button_press_mode == "SHORTEST_SINGLE_PRESS":
                # Wait until o_valid is low for 5 cycles
                if self.o_valid is not None:
                    valid_low_cycles = 0
                    while valid_low_cycles < 5:
                        await RisingEdge(self.clk)
                        if self.o_valid.value == 0:
                            valid_low_cycles += 1
                        else:
                            valid_low_cycles = 0
                else:
                    await ClockCycles(self.clk, self.no_valid_delay_cyc)  # Wait 100 cycles if no o_valid provided
                # If op, press for 1 cycle after a falling edge
                if signal_name in ["AC", "+", "-", "*", "/", "=", "(-)"]:
                    await FallingEdge(self.clk)
                    pin_map = {
                        "AC": self.i_ac_pin,
                        "+": self.i_add_pin,
                        "-": self.i_sub_pin,
                        "*": self.i_mul_pin,
                        "/": self.i_div_pin,
                        "=": self.i_eq_pin,
                        "(-)": self.i_neg_pin
                    }
                    pin = pin_map[signal_name]
                    pin.value = Force(1)
                    await FallingEdge(self.clk)
                    pin.value = Force(0)
                else:
                    # If digit, wait for matching word line, press for 1 cycle
                    wl_val, bl_val = self.button_bit_line_mapping[signal_name]
                    while True:
                        await FallingEdge(self.clk)
                        if self.o_word_lines.value == wl_val:
                            break
                    self.i_bit_lines.value = Force(bl_val)
                    await FallingEdge(self.clk)
                    self.i_bit_lines.value = Force(0b0000)
            else:
                raise ValueError(f"Unknown button_press_mode: {self.button_press_mode}")


class OutputDriverMonitor:
    def __init__(self, output_data_signal, output_sr_clk_signal, output_sr_latch_signal, num_values_to_read=100, expected_values_list=None):
        self._output_data_signal = output_data_signal
        self._output_sr_clk_signal = output_sr_clk_signal
        self._output_sr_latch_signal = output_sr_latch_signal
        self._num_values_to_read = num_values_to_read
        self.expected_values_list = expected_values_list
        self.data_queue = []
        # TODO: Monitor SRLatch signal, Monitor SRCLK signal on 2 separate coroutines

    async def _monitor_output(self):
        sr_bits = 0
        while True:
            # await RisingEdge
            pass


@cocotb.test(skip=os.environ.get("GATES")=="yes")
@cocotb.parametrize(
    ready_timing=["ALWAYS_ON", "RANDOM_READY"],
    button_press_mode=["SINGLE_PRESS", "MULTI_PRESS", "MULTI_HOLD_LATE_RELEASE", "SHORTEST_SINGLE_PRESS"],
    input_order=["IN_ORDER", "RANDOM_ORDER"],
    num_samples=[int(os.environ.get("NUM_SAMPLES", "100"))],
    button_hold_random_min_cyc=[5],
    button_hold_random_max_cyc=[50],
    inter_press_gap_random_min_cyc=[5],
    inter_press_gap_random_max_cyc=[50],
    ready_delay_random_min_cyc=[1],
    ready_delay_random_max_cyc=[10],
    timeout_ms=[int(os.environ.get("TIMEOUT_MS", "1000"))]
)
async def test_button_reader(dut, ready_timing, button_press_mode, input_order, num_samples, button_hold_random_min_cyc, button_hold_random_max_cyc, inter_press_gap_random_min_cyc, inter_press_gap_random_max_cyc, ready_delay_random_min_cyc, ready_delay_random_max_cyc, timeout_ms):
    cocotb.log.info(f"Starting test with ready_timing={ready_timing}, button_press_mode={button_press_mode}, input_order={input_order}, num_samples={num_samples}")

    # Collect signals
    clk = dut.clk
    rst_n = dut.rst_n
    br = dut.user_project.br_inst
    o_word_lines = br.o_word_lines
    i_bit_lines = br.i_bit_lines
    i_ac_pin = br.i_ac_pin
    i_add_pin = br.i_add_pin
    i_sub_pin = br.i_sub_pin
    i_mul_pin = br.i_mul_pin
    i_div_pin = br.i_div_pin
    i_eq_pin = br.i_eq_pin
    i_neg_pin = br.i_neg_pin
    o_data = br.o_data
    o_valid = br.o_valid
    i_ready = br.i_ready
    
    # Set the clock period to 10 us (100 KHz)
    clock = Clock(clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await ClockCycles(dut.clk, 10) # Wait 10 cycles for stable clock

    # Instantiate ButtonPressGenerator
    button_press_generator = ButtonPressGenerator(
        clk=clk,
        o_word_lines=o_word_lines,
        i_bit_lines=i_bit_lines,
        i_ac_pin=i_ac_pin,
        i_add_pin=i_add_pin,
        i_sub_pin=i_sub_pin,
        i_mul_pin=i_mul_pin,
        i_div_pin=i_div_pin,
        i_eq_pin=i_eq_pin,
        i_neg_pin=i_neg_pin,
        o_valid=o_valid,
        button_press_mode=button_press_mode,
        input_order=input_order,
        num_samples=num_samples,
        button_hold_random_min_cyc=button_hold_random_min_cyc,
        button_hold_random_max_cyc=button_hold_random_max_cyc,
        inter_press_gap_random_min_cyc=inter_press_gap_random_min_cyc,
        inter_press_gap_random_max_cyc=inter_press_gap_random_max_cyc
    )

    # Instantiate ValueReader
    value_reader = ButtonValueReader(
        signal_data=o_data,
        signal_ready=i_ready,
        signal_valid=o_valid,
        clk=clk,
        ready_mode=ready_timing,
        num_reads=num_samples,
        random_delay_min_cyc=ready_delay_random_min_cyc,
        random_delay_max_cyc=ready_delay_random_max_cyc,
        expected_values_list=button_press_generator.button_presses_generated
    )

    # Reset
    dut._log.info("Reset")
    rst_n.value = Force(0)
    # Set other inputs to default
    i_bit_lines.value = Force(0b0000)
    i_ac_pin.value = Force(0)
    i_add_pin.value = Force(0)
    i_sub_pin.value = Force(0)
    i_mul_pin.value = Force(0)
    i_div_pin.value = Force(0)
    i_eq_pin.value = Force(0)
    i_neg_pin.value = Force(0)
    i_ready.value = Force(0)
    await ClockCycles(dut.clk, 10)
    rst_n.value = Force(1)
    await ClockCycles(dut.clk, 10)

    # Begin coroutines
    reader_read_coro = cocotb.start_soon(value_reader._read_values())
    reader_set_ready_coro = cocotb.start_soon(value_reader._set_ready(ready_timing))
    button_press_press_coro = cocotb.start_soon(button_press_generator._press_buttons())

    # Wait read to be done, timeout after timeout_ms ms
    await First(reader_read_coro, Timer(timeout_ms, unit='ms'))
    if not reader_read_coro.done():
        cocotb.log.error("Test timed out waiting for value reader to finish.")
    cocotb.log.info(f"Read {len(value_reader.data_queue)} values.")

    # Check results
    expected_presses = button_press_generator.button_presses_generated
    received_values = value_reader.data_queue

    num_errors = 0
    for i, expected in enumerate(expected_presses):
        if i >= len(received_values):
            cocotb.log.error(f"Missing received value at index {i}: expected {expected}, got nothing")
            num_errors += 1
            continue
        received = received_values[i]
        if expected != received:
            cocotb.log.error(f"Mismatch at index {i}: expected {expected}, got {received}")
            num_errors += 1
        else:
            cocotb.log.info(f"Match at index {i}: {expected}")

    assert num_errors == 0, f"Test failed with {num_errors} errors."


@cocotb.test(skip=os.environ.get("GATES")=="yes")
@cocotb.parametrize(
    valid_timing=["ALWAYS_ON", "RANDOM_VALID"],
    test_2s_complement=[True, False],
    input_order=["IN_ORDER", "RANDOM_ORDER"],
    allow_error=[False, True], # Allow i_error
    num_samples=[int(os.environ.get("NUM_SAMPLES", "100"))],
    timeout_ms=[int(os.environ.get("TIMEOUT_MS", "1000"))]
)
async def test_output_driver():
    assert 1==2, "Not implemented yet."


@cocotb.test(skip=os.environ.get("GATES")=="yes")
@cocotb.parametrize(
    test_only_certain_ops=["+", "-", "*", "/", "ALL"],
    test_2s_complement=[False, True],
    input_value_range_width=[4, 8, 16], 
    operation_sequence=["SEQUENTIAL_OPS", "RANDOM_OPS"],
    input_valid_timing=["ALWAYS_ON", "RANDOM_VALID"],
    output_ready_timing=["ALWAYS_ON", "RANDOM_READY"],
    num_samples=[int(os.environ.get("NUM_SAMPLES", "100"))],
    timeout_ms=[int(os.environ.get("TIMEOUT_MS", "1000"))],
    signal_width=[DATA_WIDTH]  # Currently only 16 is supported
)
async def test_alu(dut, test_2s_complement, input_value_range_width, operation_sequence, test_only_certain_ops, input_valid_timing, output_ready_timing, num_samples, timeout_ms, signal_width):
    alu = dut.user_project.alu_inst
    cocotb.log.info(f"Starting ALU test with test_2s_complement={test_2s_complement}, operation_sequence={operation_sequence}, input_valid_timing={input_valid_timing}, output_ready_timing={output_ready_timing}, num_samples={num_samples}")

    # Initialize signals
    clk = dut.clk
    rst_n = dut.rst_n
    alu_input_a = alu.i_alu_input_a
    alu_input_b = alu.i_alu_input_b
    alu_op = alu.i_alu_input_op
    input_signed = alu.i_alu_input_signed
    input_valid = alu.i_alu_input_valid
    input_ready = alu.o_alu_input_ready
    output_result = alu.o_alu_result
    output_error = alu.o_alu_error
    output_valid = alu.o_alu_result_valid
    output_ready = alu.i_alu_result_ready

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await ClockCycles(dut.clk, 10) # Wait 10 cycles for stable clock

    # Reset
    dut._log.info("Reset")
    rst_n.value = Force(0)
    alu_input_a.value = Force(0)
    alu_input_b.value = Force(0)
    alu_op.value = Force(0)
    input_signed.value = Force(0)
    input_valid.value = Force(0)
    output_ready.value = Force(0)
    await ClockCycles(dut.clk, 10)
    rst_n.value = Force(1)
    await ClockCycles(dut.clk, 10)

    if test_2s_complement:
        input_signed.value = Force(1)
    else:
        input_signed.value = Force(0)

    def generate_test_vectors(num_samples, operation_sequence, signal_width):
        test_vectors = []
        operations = ['+', '-', '*', '/']
        max_value = 2**(input_value_range_width - 1) - 1 if test_2s_complement else 2**input_value_range_width - 1
        min_value = -2**(input_value_range_width - 1) if test_2s_complement else 0

        for i in range(num_samples):
            a = random.randint(min_value, max_value)
            b = random.randint(min_value, max_value)

            if test_only_certain_ops != "ALL":
                operations = [test_only_certain_ops]
            if operation_sequence == "SEQUENTIAL_OPS":
                op = operations[i % len(operations)]
            elif operation_sequence == "RANDOM_OPS":
                op = random.choice(operations)
            else:
                raise ValueError(f"Unknown operation_sequence: {operation_sequence}")

            # If testing division, add 5% chance of b being zero
            if op == '/' and random.random() < 0.05:
                b = 0

            test_vectors.append((a, b, op))
        return test_vectors
    test_vectors = generate_test_vectors(num_samples, operation_sequence, signal_width)

    async def generate_input_valid(input_valid_sig, input_valid_timing):
        await FallingEdge(clk)
        if input_valid_timing == "ALWAYS_ON":
            while True:
                input_valid_sig.value = Force(1)
                await FallingEdge(clk)
        elif input_valid_timing == "RANDOM_VALID":
            while True:
                input_valid_sig.value = Force(random.choice([0, 1]))
                await ClockCycles(clk, random.randint(1, 10))
                await FallingEdge(clk)
        else:
            raise ValueError(f"Unknown input_valid_timing: {input_valid_timing}")
    async def apply_inputs(input_ready_sig, input_valid_sig, input_a_sig, input_b_sig, input_op_sig, test_vectors):
        for a, b, op in test_vectors:
            # Apply inputs
            input_a_sig.value = Force(a)
            input_b_sig.value = Force(b)
            alu_op_map = {'+': 0b00, '-': 0b01, '*': 0b10, '/': 0b11}
            input_op_sig.value = Force(alu_op_map[op])
            # Wait until input_ready and input_valid are both high
            while True:
                await RisingEdge(clk)
                if input_ready_sig.value == 1 and input_valid_sig.value == 1:
                    break
            cocotb.log.info(f"Applied inputs: A={a}, B={b}, OP={op}")
            await FallingEdge(clk)
    async def generate_output_ready(output_ready_sig, output_ready_timing):
        await FallingEdge(clk)
        if output_ready_timing == "ALWAYS_ON":
            while True:
                output_ready_sig.value = Force(1)
                await FallingEdge(clk)
        elif output_ready_timing == "RANDOM_READY":
            while True:
                output_ready_sig.value = Force(random.choice([0, 1]))
                await ClockCycles(clk, random.randint(1, 10))
                await FallingEdge(clk)
        else:
            raise ValueError(f"Unknown output_ready_timing: {output_ready_timing}")
    async def monitor_outputs(output_valid_sig, output_ready_sig, output_data_sig, output_error_sig, num_samples):
        results = []
        while len(results) < num_samples:
            await RisingEdge(clk)
            if output_valid_sig.value == 1 and output_ready_sig.value == 1:
                result = int(output_data_sig.value) if not test_2s_complement else output_data_sig.value.signed_integer
                error = int(output_error_sig.value)
                results.append((result, error))
                cocotb.log.info(f"Received output: RESULT={result}, ERROR={error}")
        return results
    # Start coroutines
    input_valid_coro = cocotb.start_soon(generate_input_valid(input_valid, input_valid_timing))
    apply_inputs_coro = cocotb.start_soon(apply_inputs(input_ready, input_valid, alu_input_a, alu_input_b, alu_op, test_vectors))
    output_ready_coro = cocotb.start_soon(generate_output_ready(output_ready, output_ready_timing))
    monitor_outputs_coro = cocotb.start_soon(monitor_outputs(output_valid, output_ready, output_result, output_error, num_samples))

    # Wait for monitor to finish or timeout
    await First(monitor_outputs_coro, Timer(timeout_ms, unit='ms'))
    if not monitor_outputs_coro.done():
        cocotb.log.error("Test timed out waiting for output monitor to finish.")
    results = monitor_outputs_coro.result()
    cocotb.log.info(f"Monitor results: {results}")

    # Check results
    num_errors = 0
    for i, (a, b, op) in enumerate(test_vectors):
        expected_result = None
        expected_error = 0
        try:
            if op == '+':
                expected_result = a + b
            elif op == '-':
                expected_result = a - b
            elif op == '*':
                expected_result = a * b
            elif op == '/':
                if b == 0:
                    expected_error = 1  # Division by zero error
                else:
                    # abs value's int division then apply sign
                    expected_result = int(abs(a) // abs(b))
                    if a * b < 0:
                        expected_result = -expected_result
            # If expected result is out of range, clip the lower bits. Do not set error
            if expected_result is not None:
                if test_2s_complement:
                    bit_mask = (1 << signal_width) - 1
                    expected_result = expected_result & bit_mask
                    # Convert to signed integer representation
                    if expected_result >= (1 << (signal_width - 1)):
                        expected_result -= (1 << signal_width)
                else:
                    max_value = (1 << signal_width) - 1
                    expected_result = expected_result & max_value
        except Exception as e:
            cocotb.log.error(f"Error computing expected result for A={a}, B={b}, OP={op}: {e}")
            expected_error = 1

        received_result, received_error = results[i]
        # If error is expected, just check error flag
        if expected_error == 1 and received_error == 1:
            cocotb.log.info(f"Expected error at index {i}: A={a}, B={b}, OP={op}, ERROR={received_error}")
        elif expected_error == 1 and received_error == 0:
            cocotb.log.error(f"Missing expected error at index {i}: A={a}, B={b}, OP={op}, Expected ERROR={expected_error}, Got ERROR={received_error}")
            num_errors += 1
        elif expected_error == 0 and received_error == 1:
            cocotb.log.error(f"Unexpected error at index {i}: A={a}, B={b}, OP={op}, Expected ERROR={expected_error}, Got ERROR={received_error}")
            num_errors += 1
        elif expected_result != received_result:
            cocotb.log.error(f"Mismatch at index {i}: A={a}, B={b}, OP={op}, Expected RESULT={expected_result}, Got RESULT={received_result}")
            num_errors += 1
        else:
            cocotb.log.info(f"Match at index {i}: A={a}, B={b}, OP={op}, RESULT={received_result}, ERROR={received_error}")
    assert num_errors == 0, f"ALU test failed with {num_errors} errors."

def test_sequence_generator(include_neg_button, test_sequence_type, num_samples, sequence_length, allow_random_ac_presses):
    """
    Generate a sequence of button presses based on the specified parameters. 

    Note: This is just the button sequences. It does not concern 2's complement settings. 
    If we want to test with negative values, must check results in other parts of the testbench. (This is just the input)

    include_neg_button: str
        "NO_NEGATIVE_INPUT": never press the neg button
        "NEGATIVE_INPUT_AFTER_VAL_INPUT": only press neg button after a value input, or after = button
        "NEGATIVE_INPUT_IN_BETWEEN_VAL_INPUT": can press neg button anytime between value inputs
    test_sequence_type: str
        "ONE": always: Input number -> OP -> Input number -> = -> AC
        "SEQUENCE_BY_OP": NUM -> OP -> NUM -> OP -> NUM ... -> ... -> AC
        "SEQUENCE_AFTER_EQ": NUM -> OP -> NUM -> = -> OP -> NUM -> = ... -> AC
        "RANDOM_BUTTON_PRESS": literally press ANY button randomly 
    num_samples: int
        Number of sequences to generate
    sequence_length: int
        Number of OP/EQ/NUM presses (number input is counted as 1 press) per "sample" before AC is pressed
    allow_random_ac_presses: bool
        If True, allow random AC presses in sequences

    Returns a list of button press sequences:
    [
        Button 1,
        Button 2,
        ...
    ]
    Each value is a SINGLE button press -- so value: 0x1234 means press button '1', then '2', then '3', then '4' in sequence.
    """
    value_list = []
    possible_digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    possible_ops = ["+", "-", "*", "/"]
    neg_op = "(-)"
    ac_op = "AC"
    eq_op = "="

@cocotb.test(skip=os.environ.get("GATES")=="yes")
@cocotb.parametrize(
    test_2s_complement=[False, True],  # Whether to test in 2's complement mode
    include_neg_button=["NO_NEGATIVE_INPUT", "NEGATIVE_INPUT_AFTER_VAL_INPUT", "NEGATIVE_INPUT_IN_BETWEEN_VAL_INPUT"],  # If False, never press the neg button
    test_sequence_type=["ONE", "SEQUENCE_BY_OP", "SEQUENCE_AFTER_EQ", "RANDOM_BUTTON_PRESS"],  
        # ONE: always: AC -> Input number -> OP -> Input number -> = -> AC
        # SEQUENCE_BY_OP: AC -> NUM -> OP -> NUM -> OP -> NUM ... -> ... -> AC
        # SEQUENCE_AFTER_EQ: AC -> NUM -> OP -> NUM -> = -> OP -> NUM -> = ... -> AC
        # RANDOM_BUTTON_PRESS: literally press ANY button randomly 
        # In any sequence, AC is only pressed at end. 
    sequence_length=[5, 10, 20, 50], # Number of OP/EQ/NUM presses (number input is counted as 1 press) per "sample" before AC is pressed
    allow_random_ac_presses=[False, True],  # If True, allow random AC presses in sequences
    input_valid_timing=["ALWAYS_ON", "RANDOM_VALID"],
    output_ready_timing=["ALWAYS_ON", "RANDOM_READY"],
    num_samples=[int(os.environ.get("NUM_SAMPLES", "100"))],
    timeout_ms=[int(os.environ.get("TIMEOUT_MS", "1000"))],
    signal_width=[DATA_WIDTH]
)
async def test_core(dut, test_2s_complement, include_neg_button, test_individual_compute, input_valid_timing, output_ready_timing, num_samples, timeout_ms, signal_width):
    cocotb.log.info(f"Starting Core test with test_2s_complement={test_2s_complement}, include_neg_button={include_neg_button}, test_individual_compute={test_individual_compute}, input_valid_timing={input_valid_timing}, output_ready_timing={output_ready_timing}, num_samples={num_samples}")
    assert 1==2, "Not implemented yet."


@cocotb.test()
@cocotb.parametrize(
    button_press_mode=["SINGLE_PRESS", "MULTI_PRESS", "MULTI_HOLD_LATE_RELEASE", "SHORTEST_SINGLE_PRESS"],
    input_order=["IN_ORDER", "RANDOM_ORDER"],
    num_samples=[int(os.environ.get("NUM_SAMPLES", "100"))],
    timeout_ms=[int(os.environ.get("TIMEOUT_MS", "1000"))]
)
async def test_top(dut, button_press_mode, input_order, num_samples):
    cocotb.log.info(f"Starting top test with button_press_mode={button_press_mode}, input_order={input_order}, num_samples={num_samples}")
    # This test should generate random input sequences, and calculate expected output sequences on 7-seg display
    # Just declare the test to fail
    assert 1==2, "Not implemented yet."