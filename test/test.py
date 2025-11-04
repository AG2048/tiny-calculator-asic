# SPDX-FileCopyrightText: © 2025 Andy Gong
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.handle import Force, Release, Freeze
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, ValueChange, Edge, Timer, Combine, First, with_timeout
import os
import random

DATA_WIDTH = 16
NUM_DISPLAYS = 5

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
    def __init__(self, clk, o_word_lines, i_bit_lines, i_ac_pin, i_add_pin, i_sub_pin, i_mul_pin, i_div_pin, i_eq_pin, i_neg_pin, o_valid=None, button_press_mode="SINGLE_PRESS", input_order="IN_ORDER", num_samples=100, button_hold_random_min_cyc=5, button_hold_random_max_cyc=200, inter_press_gap_random_min_cyc=5, inter_press_gap_random_max_cyc=200, no_valid_delay_cyc=10):
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
            await ClockCycles(self.clk, self.no_valid_delay_cyc)  # Wait 10 cycles if no o_valid provided
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

    # Release all forces
    rst_n.value = Release()
    i_bit_lines.value = Release()
    i_ac_pin.value = Release()
    i_add_pin.value = Release()
    i_sub_pin.value = Release()
    i_mul_pin.value = Release()
    i_div_pin.value = Release()
    i_eq_pin.value = Release()
    i_neg_pin.value = Release()
    i_ready.value = Release()

    assert num_errors == 0, f"Test failed with {num_errors} errors."


@cocotb.test(skip=os.environ.get("GATES")=="yes")
@cocotb.parametrize(
    valid_timing=["ALWAYS_ON", "RANDOM_VALID"],
    test_neg_displays=[False, True],
    input_order=["IN_ORDER", "RANDOM_ORDER"],
    allow_error=[False, True], # Allow i_error = 1 with 10% chance
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
    
    # Release all signals
    rst_n.value = Release()
    alu_input_a.value = Release()
    alu_input_b.value = Release()
    alu_op.value = Release()
    input_signed.value = Release()
    input_valid.value = Release()
    output_ready.value = Release()

    assert num_errors == 0, f"ALU test failed with {num_errors} errors."

def test_sequence_generator(include_neg_button, test_sequence_type, num_samples, sequence_length, allow_random_ac_presses, test_overflow, data_width, test_2s_complement):
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
    test_overflow: bool
        If True, allow input values that may be over limit (based on data_width and 2's complement setting)
    data_width: int
        Width of data (e.g., 4, 8, 16)
    test_2s_complement: bool
        If True, test in 2's complement mode (input now ranges from -2^(data_width-1) to 2^(data_width-1)-1)

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

    possible_value_min = 0 if not test_2s_complement else - (1 << (data_width - 1))
    possible_value_max = (1 << data_width) -1 if not test_2s_complement else (1 << (data_width -1)) -1
    if include_neg_button == "NO_NEGATIVE_INPUT":
        possible_value_min = max(0, possible_value_min)

    def add_number_input():
        # First generate the value
        number_input = random.randint(possible_value_min, possible_value_max)
        
        # split number input into HEX digits from MSB to LSB
        number_input_breakdown = []
        if number_input < 0:
            abs_number_input = -number_input
        else:
            abs_number_input = number_input
        num_hex_digits = (data_width + 3) // 4
        for digit_idx in range(num_hex_digits-1, -1, -1):
            hex_digit = (abs_number_input >> (digit_idx *4)) & 0xF
            if len(number_input_breakdown) == 0 and hex_digit == 0:
                # Skip leading zeros
                continue
            number_input_breakdown.append(possible_digits[hex_digit])

        # Generate negative button presses
        num_negative_button_presses = random.randint(0, 3)
        if number_input < 0:
            num_negative_button_presses = num_negative_button_presses * 2 + 1
        else:
            num_negative_button_presses = num_negative_button_presses * 2
        if include_neg_button == "NO_NEGATIVE_INPUT":
            num_negative_button_presses = 0
        elif include_neg_button == "NEGATIVE_INPUT_AFTER_VAL_INPUT":
            if number_input < 0:
                number_input_breakdown.append("(-)")
        elif include_neg_button == "NEGATIVE_INPUT_IN_BETWEEN_VAL_INPUT":
            # Note this will be ignored for not 2's comp mode
            for _ in range(num_negative_button_presses):
                number_input_breakdown.insert(random.randint(0, len(number_input_breakdown)), "(-)")
        else:
            raise ValueError(f"Unknown include_neg_button: {include_neg_button}")

        # If test overflow, add randomly 0 to 3 digits at end
        if test_overflow:
            num_extra_digits = random.randint(0, 3)
            for _ in range(num_extra_digits):
                extra_digit = random.choice(possible_digits)
                number_input_breakdown.append(extra_digit)
        
        value_list.extend(number_input_breakdown)
    
    for sample_idx in range(num_samples):
        if sample_idx > 0:
            # Add AC at start of new sample
            value_list.append(ac_op)
        sequence_count = 0
        while sequence_count < sequence_length:
            if test_sequence_type == "ONE":
                # First generate the value
                add_number_input()
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break

                # Generate op
                value_list.append(random.choice(possible_ops))
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break

                # Generate next number input
                add_number_input()
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break

                # Generate equal sign
                value_list.append(eq_op)
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break

            elif test_sequence_type == "SEQUENCE_BY_OP":
                # First generate the value
                add_number_input()
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break

                # Generate op
                value_list.append(random.choice(possible_ops))
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break
            elif test_sequence_type == "SEQUENCE_AFTER_EQ":
                # Generate a value if it's the very first one
                if sequence_count == 0:
                    add_number_input()
                    sequence_count += 1
                    # Randomly add AC presses if allowed
                    if allow_random_ac_presses:
                        if random.random() < 0.1:  # 10% chance to add AC press
                            value_list.append(ac_op)
                            # Do not increment sequence_count for AC press

                    if sequence_count >= sequence_length:
                        break

                # Generate op
                value_list.append(random.choice(possible_ops))
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break

                # Generate next number input
                add_number_input()
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break

                # Generate equal sign
                value_list.append(eq_op)
                sequence_count += 1
                # Randomly add AC presses if allowed
                if allow_random_ac_presses:
                    if random.random() < 0.1:  # 10% chance to add AC press
                        value_list.append(ac_op)
                        # Do not increment sequence_count for AC press

                if sequence_count >= sequence_length:
                    break
            elif test_sequence_type == "RANDOM_BUTTON_PRESS":
                button_options = ["NUMBER", "NEG", "OP", "EQ"]
                button_choice = random.choice(button_options)
                if button_choice == "NUMBER":
                    add_number_input()
                    sequence_count += 1
                    # Randomly add AC presses if allowed
                    if allow_random_ac_presses:
                        if random.random() < 0.1:  # 10% chance to add AC press
                            value_list.append(ac_op)
                            # Do not increment sequence_count for AC press

                    if sequence_count >= sequence_length:
                        break
                elif button_choice == "NEG":
                    if include_neg_button == "NO_NEGATIVE_INPUT":
                        continue  # Skip this choice
                    value_list.append(neg_op)
                    # This case it counts towards sequence length
                    sequence_count += 1
                    # Randomly add AC presses if allowed
                    if allow_random_ac_presses:
                        if random.random() < 0.1:  # 10% chance to add AC press
                            value_list.append(ac_op)
                            # Do not increment sequence_count for AC press
                    if sequence_count >= sequence_length:
                        break
                elif button_choice == "OP":
                    value_list.append(random.choice(possible_ops))
                    sequence_count += 1
                    # Randomly add AC presses if allowed
                    if allow_random_ac_presses:
                        if random.random() < 0.1:  # 10% chance to add AC press
                            value_list.append(ac_op)
                            # Do not increment sequence_count for AC press

                    if sequence_count >= sequence_length:
                        break
                elif button_choice == "EQ":
                    value_list.append(eq_op)
                    sequence_count += 1
                    # Randomly add AC presses if allowed
                    if allow_random_ac_presses:
                        if random.random() < 0.1:  # 10% chance to add AC press
                            value_list.append(ac_op)
                            # Do not increment sequence_count for AC press

                    if sequence_count >= sequence_length:
                        break
            else:
                raise ValueError(f"Unknown test_sequence_type: {test_sequence_type}")
    return value_list

def test_sequence_expected_display_and_op_status(test_sequence, data_width, num_displays, test_2s_complement):
    """
    Given a test sequence of button presses, compute the expected display values and operation status after each button press.

    Returns:
    expected_displays: list of expected display values after each button press
        This can be a number (signed or unsigned based on test_2s_complement, leading 0 must not be shown, if result overflows, cap to DATA_WIDTH, and what's shown is limited to NUM_DISPLAYS digits minus "-" if negative),
                      "Err" (error)
                      "NONE"
    expected_op_status: list of expected operation status after each button press 
        This can be "NONE" (no op should show before next button press), 
                    "+", "-", "*", "/",
                    "HOLD" (Nothing should change on display until next button press)
    """
    expected_displays = ["0"] # Initial display is 0
    expected_op_status = ["NONE"] # Initial op status is NONE

    number_inputs = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    operation_inputs = ["+", "-", "*", "/"]
    neg_input = "(-)"
    ac_input = "AC"
    eq_input = "="
    def convert_number_to_display_string(number, num_displays):
        if number == "Err":
            return "Err"
        if number == 0:
            return "0"
        is_negative = number < 0
        hex_str = hex(abs(number))[2:].upper()  # Convert to hex string without '0x' prefix
        # Trim to fit num_displays
        if is_negative:
            max_digits = num_displays - 1
        else:
            max_digits = num_displays
        if len(hex_str) > max_digits:
            # Overflow, Cut off higher bits
            hex_str = hex_str[-max_digits:]
        if is_negative:
            hex_str = "-" + hex_str
        return hex_str

    number_a = 0
    number_b = 0
    current_op = None

    status = "INPUT_A" # Or INPUT_B_NO_VAL, INPUT_B_AFTER_VAL, SHOWN_RESULT, ERROR_SHOWN
    input_is_neg = False

    for button in test_sequence:
        if status == "INPUT_A":
            if button in number_inputs:
                digit_value = int(button, 16)
                if input_is_neg and test_2s_complement:
                    digit_value = -digit_value
                temp_result = number_a * 16 + digit_value
                # Check for overflow
                if test_2s_complement:
                    min_value = - (1 << (data_width - 1))
                    max_value = (1 << (data_width - 1)) - 1
                else:
                    min_value = 0
                    max_value = (1 << data_width) - 1
                if temp_result < min_value or temp_result > max_value:
                    # Overflow, ignore this digit input
                    expected_displays.append("NONE")
                    expected_op_status.append("HOLD")
                    continue
                number_a = temp_result
                # Update display
                expected_displays.append(convert_number_to_display_string(number_a, num_displays))
                expected_op_status.append("NONE")
            elif button == neg_input:
                input_is_neg = not input_is_neg
                if not test_2s_complement:
                    input_is_neg = False
                    expected_displays.append(convert_number_to_display_string(number_a, num_displays))
                    expected_op_status.append("NONE")
                    continue
                if number_a == 0:
                    expected_displays.append("0")
                    expected_op_status.append("NONE")
                elif number_a == -2**(data_width - 1) and test_2s_complement:
                    # Cannot negate minimum value in 2's complement
                    expected_displays.append(convert_number_to_display_string(number_a, num_displays))
                    expected_op_status.append("NONE")
                else:
                    number_a = -number_a
                    expected_displays.append(convert_number_to_display_string(number_a, num_displays))
                    expected_op_status.append("NONE")
            elif button in operation_inputs:
                current_op = button
                status = "INPUT_B_NO_VAL"
                number_b = 0
                input_is_neg = False
                expected_displays.append("NONE")
                expected_op_status.append(current_op)
            elif button == eq_input:
                # Nothing happens
                expected_displays.append("NONE")
                expected_op_status.append("NONE")
            elif button == ac_input:
                # Reset everything
                number_a = 0
                number_b = 0
                current_op = None
                status = "INPUT_A"
                input_is_neg = False
                expected_displays.append("0")
                expected_op_status.append("NONE")
            else:
                # Unknown button, error
                raise ValueError(f"Unknown button input: {button}")
        elif status == "INPUT_B_NO_VAL":
            if button in number_inputs:
                digit_value = int(button, 16)
                if input_is_neg and test_2s_complement:
                    digit_value = -digit_value
                temp_result = number_b * 16 + digit_value
                # Check for overflow
                if test_2s_complement:
                    min_value = - (1 << (data_width - 1))
                    max_value = (1 << (data_width - 1)) - 1
                else:
                    min_value = 0
                    max_value = (1 << data_width) - 1
                if temp_result < min_value or temp_result > max_value:
                    # Overflow, ignore this digit input
                    expected_displays.append("NONE")
                    expected_op_status.append("HOLD")
                    continue
                number_b = temp_result
                status = "INPUT_B_AFTER_VAL"
                # Update display
                expected_displays.append(convert_number_to_display_string(number_b, num_displays))
                expected_op_status.append("HOLD")
            elif button == neg_input:
                input_is_neg = not input_is_neg
                if not test_2s_complement:
                    input_is_neg = False
                    expected_displays.append("NONE")
                    expected_op_status.append("HOLD")
                    continue
                expected_displays.append("NONE")
                expected_op_status.append("HOLD")
            elif button in operation_inputs:
                # Change operation
                current_op = button
                expected_displays.append("NONE")
                expected_op_status.append(current_op)
            elif button == eq_input:
                number_b = number_a  # For A OP A
                # Calculate A OP A
                if current_op == "+":
                    result = number_a + number_a
                elif current_op == "-":
                    result = number_a - number_a
                elif current_op == "*": 
                    result = number_a * number_a
                elif current_op == "/":
                    if number_a == 0:
                        result = "Err"
                    else:
                        result = int(abs(number_a) // abs(number_a))
                        if number_a * number_a < 0:
                            result = -result
                else:
                    raise ValueError(f"Unknown operation: {current_op}")
                # Check for overflow
                if result != "Err":
                    if test_2s_complement:
                        bit_mask = (1 << data_width) - 1
                        result = result & bit_mask
                        # Convert to signed integer representation
                        if result >= (1 << (data_width - 1)):
                            result -= (1 << data_width)
                    else:
                        max_value = (1 << data_width) - 1
                        result = result & max_value
                number_a = result if result != "Err" else 0
                if result == "Err":
                    status = "ERROR_SHOWN"
                    expected_displays.append("Err")
                    expected_op_status.append("NONE")
                else:
                    status = "SHOWN_RESULT"
                    expected_displays.append(convert_number_to_display_string(result, num_displays))
                    expected_op_status.append("HOLD")
            elif button == ac_input:
                # Reset everything
                number_a = 0
                number_b = 0
                current_op = None
                status = "INPUT_A"
                input_is_neg = False
                expected_displays.append("0")
                expected_op_status.append("NONE")
            else:
                # Unknown button, error
                raise ValueError(f"Unknown button input: {button}")
        elif status == "INPUT_B_AFTER_VAL":
            if button in number_inputs:
                digit_value = int(button, 16)
                if input_is_neg and test_2s_complement:
                    digit_value = -digit_value
                temp_result = number_b * 16 + digit_value
                # Check for overflow
                if test_2s_complement:
                    min_value = - (1 << (data_width - 1))
                    max_value = (1 << (data_width - 1)) - 1
                else:
                    min_value = 0
                    max_value = (1 << data_width) - 1
                if temp_result < min_value or temp_result > max_value:
                    # Overflow, ignore this digit input
                    expected_displays.append("NONE")
                    expected_op_status.append("HOLD")
                    continue
                number_b = temp_result
                # Update display
                expected_displays.append(convert_number_to_display_string(number_b, num_displays))
                expected_op_status.append("HOLD")
            elif button == neg_input:
                input_is_neg = not input_is_neg
                if not test_2s_complement:
                    input_is_neg = False
                    expected_displays.append(convert_number_to_display_string(number_b, num_displays))
                    expected_op_status.append("HOLD")
                    continue
                if number_b == 0:
                    expected_displays.append("0")
                    expected_op_status.append("HOLD")
                elif number_b == -2**(data_width - 1) and test_2s_complement:
                    # Cannot negate minimum value in 2's complement
                    expected_displays.append(convert_number_to_display_string(number_b, num_displays))
                    expected_op_status.append("HOLD")
                else:
                    number_b = -number_b
                    expected_displays.append(convert_number_to_display_string(number_b, num_displays))
                    expected_op_status.append("HOLD")
            elif button in operation_inputs:
                # Calculate A OP B first
                if current_op == "+":
                    result = number_a + number_b
                elif current_op == "-":
                    result = number_a - number_b
                elif current_op == "*": 
                    result = number_a * number_b
                elif current_op == "/":
                    if number_b == 0:
                        result = "Err"
                    else:
                        result = int(abs(number_a) // abs(number_b))
                        if number_a * number_b < 0:
                            result = -result
                else:
                    raise ValueError(f"Unknown operation: {current_op}")
                # Check for overflow
                if result != "Err":
                    if test_2s_complement:
                        bit_mask = (1 << data_width) - 1
                        result = result & bit_mask
                        # Convert to signed integer representation
                        if result >= (1 << (data_width - 1)):
                            result -= (1 << data_width)
                    else:
                        max_value = (1 << data_width) - 1
                        result = result & max_value
                number_a = result if result != "Err" else 0
                number_b = number_b
                current_op = button
                if result == "Err":
                    status = "ERROR_SHOWN"
                    expected_displays.append("Err")
                    expected_op_status.append("NONE")
                else:
                    status = "INPUT_B_NO_VAL"
                    number_b = 0
                    input_is_neg = False
                    expected_displays.append(convert_number_to_display_string(result, num_displays))
                    expected_op_status.append(current_op)
            elif button == eq_input:
                # Calculate A OP B
                if current_op == "+":
                    result = number_a + number_b
                elif current_op == "-":
                    result = number_a - number_b
                elif current_op == "*": 
                    result = number_a * number_b
                elif current_op == "/":
                    if number_b == 0:
                        result = "Err"
                    else:
                        result = int(abs(number_a) // abs(number_b))
                        if number_a * number_b < 0:
                            result = -result
                else:
                    raise ValueError(f"Unknown operation: {current_op}")
                # Check for overflow
                if result != "Err":
                    if test_2s_complement:
                        bit_mask = (1 << data_width) - 1
                        result = result & bit_mask
                        # Convert to signed integer representation
                        if result >= (1 << (data_width - 1)):
                            result -= (1 << data_width)
                    else:
                        max_value = (1 << data_width) - 1
                        result = result & max_value
                number_a = result if result != "Err" else 0
                if result == "Err":
                    status = "ERROR_SHOWN"
                    expected_displays.append("Err")
                    expected_op_status.append("NONE")
                else:
                    status = "SHOWN_RESULT"
                    expected_displays.append(convert_number_to_display_string(result, num_displays))
                    expected_op_status.append("HOLD")
            elif button == ac_input:
                # Reset everything
                number_a = 0
                number_b = 0
                current_op = None
                status = "INPUT_A"
                input_is_neg = False
                expected_displays.append("0")
                expected_op_status.append("NONE")
            else:
                # Unknown button, error
                raise ValueError(f"Unknown button input: {button}")
        elif status == "SHOWN_RESULT":
            if button in number_inputs:
                # Start new input A
                input_is_neg = False
                digit_value = int(button, 16)
                if input_is_neg and test_2s_complement:
                    digit_value = -digit_value
                temp_result = digit_value
                # Check for overflow
                if test_2s_complement:
                    min_value = - (1 << (data_width - 1))
                    max_value = (1 << (data_width - 1)) - 1
                else:
                    min_value = 0
                    max_value = (1 << data_width) - 1
                if temp_result < min_value or temp_result > max_value:
                    # Overflow, ignore this digit input
                    continue
                number_a = temp_result
                status = "INPUT_A"
                # Update display
                expected_displays.append(convert_number_to_display_string(number_a, num_displays))
                expected_op_status.append("NONE")
            elif button == neg_input:
                if test_2s_complement:
                    # Flip A
                    if number_a != 0 and number_a != -2**(data_width - 1):
                        number_a = -number_a
                # Show updated A
                expected_displays.append(convert_number_to_display_string(number_a, num_displays))
                expected_op_status.append("HOLD")
            elif button in operation_inputs:
                current_op = button
                status = "INPUT_B_NO_VAL"
                number_b = 0
                input_is_neg = False
                expected_displays.append("NONE")
                expected_op_status.append(current_op)
            elif button == eq_input:
                # Calculate A OP B
                if current_op == "+":
                    result = number_a + number_b
                elif current_op == "-":
                    result = number_a - number_b
                elif current_op == "*": 
                    result = number_a * number_b
                elif current_op == "/":
                    if number_b == 0:
                        result = "Err"
                    else:
                        result = int(abs(number_a) // abs(number_b))
                        if number_a * number_b < 0:
                            result = -result
                else:
                    raise ValueError(f"Unknown operation: {current_op}")
                # Check for overflow
                if result != "Err":
                    if test_2s_complement:
                        bit_mask = (1 << data_width) - 1
                        result = result & bit_mask
                        # Convert to signed integer representation
                        if result >= (1 << (data_width - 1)):
                            result -= (1 << data_width)
                    else:
                        max_value = (1 << data_width) - 1
                        result = result & max_value
                number_a = result if result != "Err" else 0
                if result == "Err":
                    status = "ERROR_SHOWN"
                    expected_displays.append("Err")
                    expected_op_status.append("NONE")
                else:
                    status = "SHOWN_RESULT"
                    expected_displays.append(convert_number_to_display_string(result, num_displays))
                    expected_op_status.append("HOLD")
            elif button == ac_input:
                # Reset everything
                number_a = 0
                number_b = 0
                current_op = None
                status = "INPUT_A"
                input_is_neg = False
                expected_displays.append("0")
                expected_op_status.append("NONE")
            else:
                # Unknown button, error
                raise ValueError(f"Unknown button input: {button}")
        elif status == "ERROR_SHOWN":
            if button == ac_input:
                # Reset everything
                number_a = 0
                number_b = 0
                current_op = None
                status = "INPUT_A"
                input_is_neg = False
                expected_displays.append("0")
                expected_op_status.append("NONE")
            else:
                # Ignore all other inputs
                expected_displays.append("NONE")
                expected_op_status.append("NONE")
        else:
            raise ValueError(f"Unknown status: {status}")
    return expected_displays, expected_op_status

def print_generated_test_sequence_and_expected_results():
    """
    test sequence options:
    include_neg_button, test_sequence_type, num_samples, sequence_length, allow_random_ac_presses, test_overflow, data_width, test_2s_complement

    DATA_WIDTH = 16
    display_result need num_displays = 5

    Prints out generated test sequences and expected results for debugging.
    """
    for include_neg_button in ["NO_NEGATIVE_INPUT", "NEGATIVE_INPUT_AFTER_VAL_INPUT", "NEGATIVE_INPUT_IN_BETWEEN_VAL_INPUT"]:
        for test_sequence_type in ["ONE", "SEQUENCE_BY_OP", "SEQUENCE_AFTER_EQ", "RANDOM_BUTTON_PRESS"]:
            for num_samples in [2]:
                for sequence_length in [10]:
                    for allow_random_ac_presses in [False, True]:
                        for test_overflow in [False, True]:
                            for test_2s_complement in [False, True]:
                                print(f"--- Generated Test Sequence with include_neg_button={include_neg_button}, test_sequence_type={test_sequence_type}, num_samples={num_samples}, sequence_length={sequence_length}, allow_random_ac_presses={allow_random_ac_presses}, test_overflow={test_overflow}, test_2s_complement={test_2s_complement} ---")
                                test_sequence = test_sequence_generator(include_neg_button, test_sequence_type, num_samples, sequence_length, allow_random_ac_presses, test_overflow, DATA_WIDTH, test_2s_complement)
                                expected_displays, expected_op_status = test_sequence_expected_display_and_op_status(test_sequence, DATA_WIDTH, NUM_DISPLAYS, test_2s_complement)
                                for idx in range(len(test_sequence)):
                                    print(f"Button Press: {test_sequence[idx]:<5} | Expected Display: {expected_displays[idx+1]:<8} | Expected Op Status: {expected_op_status[idx+1]}")
                                print("\n\n\n\n\n")

@cocotb.test(skip=os.environ.get("GATES")=="yes")
@cocotb.parametrize(
    test_2s_complement=[False, True],  # Whether to test in 2's complement mode
    test_input_with_overflow=[False, True],  # Whether to include inputs that cause overflow (outside of valid range depending on 2's complement setting)
    include_neg_button=["NO_NEGATIVE_INPUT", "NEGATIVE_INPUT_AFTER_VAL_INPUT", "NEGATIVE_INPUT_IN_BETWEEN_VAL_INPUT"],  # If False, never press the neg button
    test_sequence_type=["ONE", "SEQUENCE_BY_OP", "SEQUENCE_AFTER_EQ", "RANDOM_BUTTON_PRESS"],  
        # ONE: always: AC -> Input number -> OP -> Input number -> = -> AC
        # SEQUENCE_BY_OP: AC -> NUM -> OP -> NUM -> OP -> NUM ... -> ... -> AC
        # SEQUENCE_AFTER_EQ: AC -> NUM -> OP -> NUM -> = -> OP -> NUM -> = ... -> AC
        # RANDOM_BUTTON_PRESS: literally press ANY button randomly 
        # In any sequence, AC is only pressed at end. 
    sequence_length=[5, 50], # Number of OP/EQ/NUM presses (number input is counted as 1 press) per "sample" before AC is pressed
    allow_random_ac_presses=[False, True],  # If True, allow random AC presses in sequences
    input_valid_timing=["ALWAYS_ON", "RANDOM_VALID"],
    output_ready_timing=["ALWAYS_ON", "RANDOM_READY"],
    num_samples=[int(os.environ.get("NUM_SAMPLES", "100"))],
    timeout_ms=[int(os.environ.get("TIMEOUT_MS", "1000"))],
    signal_width=[DATA_WIDTH],
    num_displays=[NUM_DISPLAYS]
)
async def test_core(dut, test_2s_complement, test_input_with_overflow, include_neg_button, test_sequence_type, sequence_length, allow_random_ac_presses, input_valid_timing, output_ready_timing, num_samples, timeout_ms, signal_width, num_displays):
    core = dut.user_project.cc_inst
    cocotb.log.info(f"Starting Core test with test_2s_complement={test_2s_complement}, test_input_with_overflow={test_input_with_overflow}, include_neg_button={include_neg_button}, test_sequence_type={test_sequence_type}, sequence_length={sequence_length}, allow_random_ac_presses={allow_random_ac_presses}, input_valid_timing={input_valid_timing}, output_ready_timing={output_ready_timing}, num_samples={num_samples}, timeout_ms={timeout_ms}, signal_width={signal_width}, num_displays={num_displays}")

    clk = dut.clk
    rst_n = dut.rst_n

    i_button_data = core.i_button_data
    i_button_valid = core.i_button_valid
    o_button_ready = core.o_button_ready
    i_2s_comp_mode = core.i_2s_comp_mode

    o_add_state_display = core.o_add_state_display
    o_sub_state_display = core.o_sub_state_display
    o_mul_state_display = core.o_mul_state_display
    o_div_state_display = core.o_div_state_display
    o_display_data = core.o_display_data
    o_display_error = core.o_display_error
    o_display_value_is_neg = core.o_display_value_is_neg
    o_display_valid = core.o_display_valid
    i_display_ready = core.i_display_ready

    # Set the clock
    clock = Clock(clk, 10, unit="ns")  # 100 MHz clock
    cocotb.start_soon(clock.start())
    await ClockCycles(clk, 10) # Let the clock run for a few cycles

    # Reset the 
    cocotb.log.info("Resetting DUT...")
    rst_n.value = Force(0)
    i_button_data.value = Force(0)
    i_button_valid.value = Force(0)
    i_2s_comp_mode.value = Force(1 if test_2s_complement else 0)
    i_display_ready.value = Force(0)
    await ClockCycles(clk, 10)  # Wait for a few clock cycles
    rst_n.value = Force(1)

    test_samples = test_sequence_generator(include_neg_button, test_sequence_type, num_samples, sequence_length, allow_random_ac_presses, test_input_with_overflow, signal_width, test_2s_complement)
    expected_displays, expected_op_status = test_sequence_expected_display_and_op_status(test_samples, signal_width, num_displays, test_2s_complement)

    async def generate_input_valid(input_valid_sig, input_valid_timing):
        if input_valid_timing == "ALWAYS_ON":
            while True:
                input_valid_sig.value = Force(1)
                await RisingEdge(clk)
        elif input_valid_timing == "RANDOM_VALID":
            while True:
                input_valid_sig.value = Force(random.choice([0, 1]))
                await ClockCycles(clk, random.randint(1, 10))
                await FallingEdge(clk)
        else:
            raise ValueError(f"Unknown input_valid_timing: {input_valid_timing}")

    async def apply_inputs(input_ready_sig, input_valid_sig, input_sig, test_samples):
        await FallingEdge(clk)
        sample_idx = 0
        while sample_idx < len(test_samples):
            # Apply values
            sample = test_samples[sample_idx]
            if sample in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]:
                input_sig.value = Force(int(sample, 16))
            elif sample == "(-)":
                input_sig.value = Force(0b10110) # NEG button code
            elif sample == "+":
                input_sig.value = Force(0b10000) # ADD button code
            elif sample == "-":
                input_sig.value = Force(0b10001) # SUB button code
            elif sample == "*":
                input_sig.value = Force(0b10010) # MUL button code
            elif sample == "/":
                input_sig.value = Force(0b10011) # DIV button code
            elif sample == "=":
                input_sig.value = Force(0b10100) # EQ button code
            elif sample == "AC":
                input_sig.value = Force(0b10101) # AC button code
            else:
                raise ValueError(f"Unknown sample input: {sample}")
            while True:
                await RisingEdge(clk)
                if input_ready_sig.value == 1 and input_valid_sig.value == 1:
                    break
            cocotb.log.info(f"Applied input sample: {sample} at index {sample_idx}")
            sample_idx += 1
            await FallingEdge(clk)

    async def generate_output_ready(output_ready_sig, output_ready_timing):
        if output_ready_timing == "ALWAYS_ON":
            while True:
                output_ready_sig.value = Force(1)
                await RisingEdge(clk)
        elif output_ready_timing == "RANDOM_READY":
            while True:
                output_ready_sig.value = Force(random.choice([0, 1]))
                await ClockCycles(clk, random.randint(1, 10))
                await FallingEdge(clk)
        else:
            raise ValueError(f"Unknown output_ready_timing: {output_ready_timing}")

    async def monitor_outputs(output_ready_sig, output_valid_sig, display_data_sig, display_error_sig, display_value_is_neg_sig, expected_displays):
        results = []
        while len(results) < len(expected_displays):
            await RisingEdge(clk)
            if output_valid_sig.value == 1 and output_ready_sig.value == 1:
                # Read output
                unsigned_value = int(display_data_sig.value)
                is_error = int(display_error_sig.value)
                is_neg = int(display_value_is_neg_sig.value)
                if is_error:
                    display_str = "Err"
                else:
                    if is_neg:
                        signed_value = -unsigned_value
                    else:
                        signed_value = unsigned_value
                    # Convert to hex string
                    hex_str = hex(abs(unsigned_value))[2:].upper()
                    if signed_value < 0:
                        hex_str = "-" + hex_str
                    display_str = hex_str
                results.append(display_str)
                if display_str != expected_displays[len(results)-1]:
                    cocotb.log.error(f"Mismatch at output {len(results)-1}: got {display_str}, expected {expected_displays[len(results)-1]}")
                else:
                    cocotb.log.info(f"Captured output display: {display_str} matches expected.")
                # Skip "NONE"
                while len(results) < len(expected_displays) and expected_displays[len(results)] == "NONE":
                    results.append("NONE")
        return results

    async def monitor_op_status(add_display_sig, sub_display_sig, mul_display_sig, div_display_sig, button_input_valid_sig, button_input_ready_sig, expected_op_status):
        """
        If value expected is NONE, make sure no op display is turned on prior to next input_valid && input_ready
        If value expected is +, -, *, /, make sure corresponding op display is turned on (with a rising edge) prior to next input_valid && input_ready (nothing else should be on)
        If value expected is HOLD, make sure op display remains unchanged prior to next input_valid && input_ready
        This just returns error counts, not the actual op status values.
        """
        error_counts = 0
        current_add_status = 0
        current_sub_status = 0
        current_mul_status = 0
        current_div_status = 0
        previous_add_status = 0
        previous_sub_status = 0
        previous_mul_status = 0
        previous_div_status = 0
        sample_idx = 0
        rising_edge_detected = False
        while sample_idx < len(expected_op_status) - 1: # Skip the last one, since no next input after that
            await RisingEdge(clk)
            # Process first, then wait for next input valid & ready
            # Set previous statuses
            previous_add_status = current_add_status
            previous_sub_status = current_sub_status
            previous_mul_status = current_mul_status
            previous_div_status = current_div_status
            # Read current statuses
            current_add_status = int(add_display_sig.value)
            current_sub_status = int(sub_display_sig.value)
            current_mul_status = int(mul_display_sig.value)
            current_div_status = int(div_display_sig.value)
            # Print all previous and current statuses for debugging
            # cocotb.log.info(f"At sample {sample_idx}, Previous Op Status: ADD={previous_add_status}, SUB={previous_sub_status}, MUL={previous_mul_status}, DIV={previous_div_status} | Current Op Status: ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
            expected_status = expected_op_status[sample_idx]
            if expected_status == "NONE":
                if current_add_status != 0 or current_sub_status != 0 or current_mul_status != 0 or current_div_status != 0:
                    cocotb.log.error(f"At sample {sample_idx}, expected NONE op status, but got ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                    error_counts += 1
            elif expected_status == "+":
                # For ops, check if a rising edge occurred. 
                if previous_add_status == 0 and current_add_status == 1:
                    rising_edge_detected = True
                # If falling edge detected, it's an error
                if previous_add_status == 1 and current_add_status == 0:
                    cocotb.log.error(f"At sample {sample_idx}, expected ADD op status, but detected falling edge.")
                    error_counts += 1
            elif expected_status == "-":
                if previous_sub_status == 0 and current_sub_status == 1:
                    rising_edge_detected = True
                # If falling edge detected, it's an error
                if previous_sub_status == 1 and current_sub_status == 0:
                    cocotb.log.error(f"At sample {sample_idx}, expected SUB op status, but detected falling edge.")
                    error_counts += 1
            elif expected_status == "*":
                if previous_mul_status == 0 and current_mul_status == 1:
                    rising_edge_detected = True
                # If falling edge detected, it's an error
                if previous_mul_status == 1 and current_mul_status == 0:
                    cocotb.log.error(f"At sample {sample_idx}, expected MUL op status, but detected falling edge.")
                    error_counts += 1
            elif expected_status == "/":
                if previous_div_status == 0 and current_div_status == 1:
                    rising_edge_detected = True
                # If falling edge detected, it's an error
                if previous_div_status == 1 and current_div_status == 0:
                    cocotb.log.error(f"At sample {sample_idx}, expected DIV op status, but detected falling edge.")
                    error_counts += 1
            elif expected_status == "HOLD":
                # Nothing should change
                if (current_add_status != previous_add_status or
                    current_sub_status != previous_sub_status or
                    current_mul_status != previous_mul_status or
                    current_div_status != previous_div_status):
                    cocotb.log.error(f"At sample {sample_idx}, expected HOLD op status, but got change from ADD={previous_add_status}, SUB={previous_sub_status}, MUL={previous_mul_status}, DIV={previous_div_status} to ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                    error_counts += 1
            else:
                cocotb.log.error(f"Unknown expected op status: {expected_status}")
                error_counts += 1

            if button_input_valid_sig.value == 1 and button_input_ready_sig.value == 1:
                # At button press, check if the "unwanted lights" are still on
                if expected_status == "NONE":
                    if current_add_status != 0 or current_sub_status != 0 or current_mul_status != 0 or current_div_status != 0:
                        cocotb.log.error(f"At sample {sample_idx}, expected NONE op status at button press, but got ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                        error_counts += 1
                elif expected_status == "+":
                    if current_add_status != 1 or current_sub_status != 0 or current_mul_status != 0 or current_div_status != 0:
                        cocotb.log.error(f"At sample {sample_idx}, expected ADD op status at button press, but got ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                        error_counts += 1
                elif expected_status == "-":
                    if current_add_status != 0 or current_sub_status != 1 or current_mul_status != 0 or current_div_status != 0:
                        cocotb.log.error(f"At sample {sample_idx}, expected SUB op status at button press, but got ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                        error_counts += 1
                elif expected_status == "*":
                    if current_add_status != 0 or current_sub_status != 0 or current_mul_status != 1 or current_div_status != 0:
                        cocotb.log.error(f"At sample {sample_idx}, expected MUL op status at button press, but got ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                        error_counts += 1
                elif expected_status == "/":
                    if current_add_status != 0 or current_sub_status != 0 or current_mul_status != 0 or current_div_status != 1:
                        cocotb.log.error(f"At sample {sample_idx}, expected DIV op status at button press, but got ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                        error_counts += 1
                # Print the expected vs actual op status immediately before this button press
                cocotb.log.info(f"At sample {sample_idx}, expected op status: {expected_status}, actual ADD={current_add_status}, SUB={current_sub_status}, MUL={current_mul_status}, DIV={current_div_status}")
                # Check if rising edge was detected for ops
                if expected_status in ["+", "-", "*", "/"] and not rising_edge_detected:
                    cocotb.log.error(f"At sample {sample_idx}, expected {expected_status} op status, but no rising edge detected.")
                    error_counts += 1
                # Move to next sample
                sample_idx += 1
                rising_edge_detected = False
        return error_counts

    # Start the result readers first
    output_display_ready_task = cocotb.start_soon(generate_output_ready(i_display_ready, output_ready_timing))
    output_display_task = cocotb.start_soon(monitor_outputs(i_display_ready, o_display_valid, o_display_data, o_display_error, o_display_value_is_neg, expected_displays))
    op_status_task = cocotb.start_soon(monitor_op_status(o_add_state_display, o_sub_state_display, o_mul_state_display, o_div_state_display, i_button_valid, o_button_ready, expected_op_status))

    # Start input valid generator
    input_valid_task = cocotb.start_soon(generate_input_valid(i_button_valid, input_valid_timing))
    apply_inputs_task = cocotb.start_soon(apply_inputs(o_button_ready, i_button_valid, i_button_data, test_samples))

    # Wait for both apply input AND output monitor to finish, or Timer(), whichever first
    await First(Combine(apply_inputs_task, output_display_task, op_status_task), Timer(timeout_ms, unit="ms"))

    # If any of the tasks are still running, kill them
    if not apply_inputs_task.done():
        cocotb.log.error("Apply inputs task did not finish before timeout.")
    if not output_display_task.done():
        cocotb.log.error("Output display monitoring task did not finish before timeout.")
    if not op_status_task.done():
        cocotb.log.error("Operation status monitoring task did not finish before timeout.")

    # Check results:
    output_displays = output_display_task.result()
    # Compare output displays with expected displays
    output_error_count = 0
    for idx in range(len(expected_displays)):
        if output_displays[idx] != expected_displays[idx]:
            cocotb.log.error(f"Final check - Mismatch at output {idx}: got {output_displays[idx]}, expected {expected_displays[idx]}")
            output_error_count += 1

    # Release all forces
    rst_n.value = Release()
    i_button_data.value = Release()
    i_button_valid.value = Release()
    i_2s_comp_mode.value = Release()
    i_display_ready.value = Release()

    assert output_error_count == 0, f"Output display monitoring detected {output_error_count} errors."
    op_status_error_count = op_status_task.result()
    assert op_status_error_count == 0, f"Operation status monitoring detected {op_status_error_count} errors."


@cocotb.test()
@cocotb.parametrize(
    # Core settings
    test_2s_complement=[False, True],  # Whether to test in 2's complement mode
    test_input_with_overflow=[False, True],  # Whether to include inputs that cause overflow (outside of valid range depending on 2's complement setting)
    include_neg_button=["NO_NEGATIVE_INPUT", "NEGATIVE_INPUT_AFTER_VAL_INPUT", "NEGATIVE_INPUT_IN_BETWEEN_VAL_INPUT"],  # If False, never press the neg button
    test_sequence_type=["ONE", "SEQUENCE_BY_OP", "SEQUENCE_AFTER_EQ", "RANDOM_BUTTON_PRESS"],  
        # ONE: always: AC -> Input number -> OP -> Input number -> = -> AC
        # SEQUENCE_BY_OP: AC -> NUM -> OP -> NUM -> OP -> NUM ... -> ... -> AC
        # SEQUENCE_AFTER_EQ: AC -> NUM -> OP -> NUM -> = -> OP -> NUM -> = ... -> AC
        # RANDOM_BUTTON_PRESS: literally press ANY button randomly 
        # In any sequence, AC is only pressed at end. 
    sequence_length=[5, 10, 20, 50], # Number of OP/EQ/NUM presses (number input is counted as 1 press) per "sample" before AC is pressed
    allow_random_ac_presses=[False, True],  # If True, allow random AC presses in sequences

    # Input settings
    button_press_mode=["SINGLE_PRESS", "MULTI_PRESS", "MULTI_HOLD_LATE_RELEASE", "SHORTEST_SINGLE_PRESS"],
    button_hold_random_min_cyc=[5],
    button_hold_random_max_cyc=[50],
    inter_press_gap_random_min_cyc=[5],
    inter_press_gap_random_max_cyc=[50],
    ready_delay_random_min_cyc=[1],
    ready_delay_random_max_cyc=[10],
    button_press_no_valid_delay_cyc=[10], # Since we won't read o_valid in this test, just set to 10 cycles

    # Test settings
    num_samples=[int(os.environ.get("NUM_SAMPLES", "100"))],
    timeout_ms=[int(os.environ.get("TIMEOUT_MS", "1000"))]
)
async def test_top(dut, test_2s_complement, include_neg_button, test_sequence_type, sequence_length, allow_random_ac_presses, button_press_mode, button_hold_random_min_cyc, button_hold_random_max_cyc, inter_press_gap_random_min_cyc, inter_press_gap_random_max_cyc, ready_delay_random_min_cyc, ready_delay_random_max_cyc, button_press_no_valid_delay_cyc, num_samples, timeout_ms):
    cocotb.log.info(f"Starting Top test with test_2s_complement={test_2s_complement}, include_neg_button={include_neg_button}, test_sequence_type={test_sequence_type}, allow_random_ac_presses={allow_random_ac_presses}, button_press_mode={button_press_mode}, num_samples={num_samples}")
    assert 1==2, "Not implemented yet."