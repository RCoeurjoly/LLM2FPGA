#include "VTop.h"

#include "verilated_vcd_c.h"

#include "signal.h"
#include <iostream>

vluint64_t timeStamp;

// Stop the simulation gracefully on ctrl-c.
volatile bool stopSimulation = false;
void handle_sigint(int) { stopSimulation = true; }

// Called by $time in Verilog.
double sc_time_stamp() { return timeStamp; }

int main(int argc, char **argv) {
  // Register graceful exit handler.
  signal(SIGINT, handle_sigint);

  Verilated::commandArgs(argc, argv);

  bool runForever = true;

  // Construct the simulated module's C++ model.
  auto &dut = *new VTop();
  char *waveformFile = getenv("SAVE_WAVE");

  VerilatedVcdC *tfp = nullptr;
  if (waveformFile) {
#ifdef TRACE
    tfp = new VerilatedVcdC();
    Verilated::traceEverOn(true);
    dut.trace(tfp, 99); // Trace 99 levels of hierarchy
    tfp->open(waveformFile);
    std::cout << "[driver] Opening trace " << waveformFile << std::endl;
#endif
  }

  std::cout << "[driver] Starting simulation" << std::endl;

  // Reset.
  dut.reset = 1;
  dut.clock = 0;

  // Run for a few cycles with reset held.
  for (timeStamp = 0; timeStamp < 8 && !Verilated::gotFinish(); timeStamp++) {
    dut.eval();
    dut.clock = !dut.clock;
    if (tfp)
      tfp->dump(timeStamp);
  }

  // Take simulation out of reset.
  dut.reset = 0;

  // Run for the specified number of cycles out of reset.
  for (; !Verilated::gotFinish() && !stopSimulation; timeStamp++) {
    dut.eval();
    dut.clock = !dut.clock;
    if (tfp)
      tfp->dump(timeStamp);
  }

  // Tell the simulator that we're going to exit. This flushes the output(s) and
  // frees whatever memory may have been allocated.
  dut.final();
  if (tfp)
    tfp->close();

  std::cout << "[driver] Ending simulation at tick #" << timeStamp << std::endl;
  return 0;
}
