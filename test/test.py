# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    # Set the input values you want to test
    dut.ui_in.value = 1 if dut.uo_out.value == 1 else 0
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 10)

    dut.ui_in.value = 0

    await ClockCycles(dut.clk, 10)

    dut._log.info("Check output values")

    dut._log.info(f"Input Value: {dut.user_project.input_value.value}")
    dut._log.info(f"Input Valid: {dut.user_project.input_valid.value}")

    # The following assersion is just an example of how to check the output values.
    # Change it to match the actual expected output of your module:
    assert dut.user_project.input_valid.value == 1, "Input valid signal should be high"
    assert dut.user_project.input_value.value == 4, "Input value should be 4"

    # Keep testing the module by changing the input values, waiting for
    # one or more clock cycles, and asserting the expected output values.
